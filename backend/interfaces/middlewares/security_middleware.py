"""
Middleware de Seguridad — Auth0 + Tenant Isolation (ASR-10).

Intercepta TODAS las peticiones API:
  1. Valida el JWT emitido por Auth0 (firma, expiración, audience)
  2. Extrae claims: email, empresa_id (custom claim), roles
  3. Inyecta un objeto user en request para uso en controladores
  4. Registra cada intento no autorizado en CloudWatch (log inmutable — ASR-10)
  5. NUNCA persiste el token JWT en BD, logs ni caché (ASR-10)

Rutas excluidas: /health/, /admin/login/, /api/schema/
"""

import logging
import os
import time
from dataclasses import dataclass
from typing import Optional

import jwt
import requests
from django.http import JsonResponse

from config.settings.env import settings
from infrastructure.aws_services.adapters import CloudWatchAuditLogger

logger = logging.getLogger(__name__)

# Rutas que no requieren autenticación
_PUBLIC_PATHS = frozenset(["/health/", "/admin/", "/api/schema/", "/api/docs/"])

# Bandera para deshabilitar autenticación en pruebas de latencia SIN seguridad.
# Permite al experimento ASR-11 medir latencia base y compararla con seguridad activa.
# NUNCA activar en producción real.
# Uso: BYPASS_AUTH_FOR_TESTING=true en .env antes de correr el JMeter sin tokens.
_BYPASS_AUTH = os.getenv("BYPASS_AUTH_FOR_TESTING", "false").lower() == "true"

# Cache de JWKS para no pedir las claves públicas en cada request
_JWKS_CACHE: dict = {"keys": None, "expires_at": 0}
_JWKS_TTL = 3600  # 1 hora


@dataclass
class AuthenticatedUser:
    """Objeto usuario inyectado en request por el middleware."""
    email: str
    empresa_id: Optional[str]
    roles: list[str]
    sub: str  # Auth0 user ID


class Auth0SecurityMiddleware:
    """
    Middleware de seguridad — implementa ASR-10 (Confidencialidad).

    Garantías:
      - 100% de accesos no autorizados bloqueados antes de llegar a datos
      - Log inmutable en CloudWatch para cada intento bloqueado
      - El JWT nunca se persiste (existe solo en memoria durante la request)
    """

    def __init__(self, get_response):
        self.get_response = get_response
        self.audit_logger = CloudWatchAuditLogger()
        self.auth0_domain = settings.AUTH0_DOMAIN
        self.audience = settings.AUTH0_AUDIENCE

    def __call__(self, request):
        # Rutas públicas: pasar sin validación
        if any(request.path.startswith(p) for p in _PUBLIC_PATHS):
            return self.get_response(request)

        # Bypass para experimento de latencia SIN seguridad (comparación ASR-11)
        if _BYPASS_AUTH:
            request.user = AuthenticatedUser(
                email="bypass@test.com",
                empresa_id=None,
                roles=[],
                sub="bypass",
            )
            return self.get_response(request)

        ip = request.META.get("REMOTE_ADDR", "unknown")
        auth_header = request.META.get("HTTP_AUTHORIZATION", "")

        # 1. Verificar presencia del header Authorization
        if not auth_header or not auth_header.startswith("Bearer "):
            return self._reject(
                ip=ip,
                user_email="anonymous",
                reason="Token ausente o malformado",
                path=request.path,
            )

        # 2. Extraer token (SOLO en memoria — ASR-10)
        token = auth_header.split(" ", 1)[1]

        # 3. Validar JWT con Auth0
        try:
            payload = self._validate_jwt(token)
        except jwt.ExpiredSignatureError:
            return self._reject(ip, "anonymous", "Token expirado", request.path)
        except jwt.InvalidAudienceError:
            return self._reject(ip, "anonymous", "Audience inválida", request.path)
        except jwt.InvalidIssuerError:
            return self._reject(ip, "anonymous", "Issuer inválido", request.path)
        except Exception as exc:
            logger.warning("JWT inválido desde IP %s: %s", ip, exc)
            return self._reject(ip, "anonymous", f"JWT inválido: {type(exc).__name__}", request.path)

        # 4. Extraer claims y poblar request.user
        email = payload.get("email") or payload.get(f"{self.auth0_domain}/email", "")
        empresa_id = payload.get(f"https://aqsf.com/empresa_id") or payload.get("empresa_id")
        roles = payload.get(f"https://aqsf.com/roles", [])

        request.user = AuthenticatedUser(
            email=email,
            empresa_id=empresa_id,
            roles=roles,
            sub=payload.get("sub", ""),
        )

        # 5. Log de acceso autorizado (auditoría completa — ASR-10)
        self.audit_logger.log_security_event(
            event_type="ACCESO_AUTORIZADO",
            user_email=email,
            ip=ip,
            action=f"GET/POST {request.path}",
        )

        # Token sale de memoria aquí — nunca se persiste ✅
        del token

        return self.get_response(request)

    # ------------------------------------------------------------------
    # Validación JWT
    # ------------------------------------------------------------------

    def _validate_jwt(self, token: str) -> dict:
        """
        Valida el JWT usando las claves públicas JWKS de Auth0.
        Las claves se cachean en memoria por 1 hora para eficiencia.
        """
        jwks = self._get_jwks()
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        # Buscar la clave pública correspondiente al kid del token
        rsa_key = {}
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                rsa_key = {
                    "kty": key["kty"],
                    "kid": key["kid"],
                    "use": key["use"],
                    "n":   key["n"],
                    "e":   key["e"],
                }
                break

        if not rsa_key:
            raise jwt.InvalidTokenError("kid no encontrado en JWKS")

        public_key = jwt.algorithms.RSAAlgorithm.from_jwk(rsa_key)
        payload = jwt.decode(
            token,
            key=public_key,
            algorithms=["RS256"],
            audience=self.audience,
            issuer=f"https://{self.auth0_domain}/",
        )
        return payload

    def _get_jwks(self) -> dict:
        """Obtiene las claves JWKS de Auth0 con caché en memoria."""
        now = time.time()
        if _JWKS_CACHE["keys"] and now < _JWKS_CACHE["expires_at"]:
            return _JWKS_CACHE["keys"]

        url = f"https://{self.auth0_domain}/.well-known/jwks.json"
        response = requests.get(url, timeout=5)
        response.raise_for_status()
        jwks = response.json()

        _JWKS_CACHE["keys"] = jwks
        _JWKS_CACHE["expires_at"] = now + _JWKS_TTL
        return jwks

    # ------------------------------------------------------------------
    # Rechazo de solicitudes no autorizadas
    # ------------------------------------------------------------------

    def _reject(self, ip: str, user_email: str, reason: str, path: str) -> JsonResponse:
        """
        Bloquea la solicitud y registra evidencia inmutable en CloudWatch (ASR-10).
        Log incluye: timestamp, IP, usuario, recurso y acción tomada.
        """
        self.audit_logger.log_security_event(
            event_type="ACCESO_BLOQUEADO",
            user_email=user_email,
            ip=ip,
            action=f"Bloqueado en {path} — Razón: {reason}",
        )
        return JsonResponse(
            {"error": "No autorizado", "detail": reason},
            status=401,
        )
