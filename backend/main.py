"""
FastAPI — Microservicio Empresas (ASR-10: Autenticación Centralizada)

Responsabilidades:
  - Gestión de Empresas (CRUD) persistidas en DynamoDB Local
  - Middleware de Seguridad Auth0 JWT: rechaza 100 % de requests no autorizados
    antes de llegar a cualquier lógica de negocio (ASR-10)
  - Audit logging inmutable en CloudWatch con IP origen y timestamp (ASR-10)

Puerto: 8001 (uvicorn — configurado en el script systemd de Terraform)

Rutas:
  GET  /health                       → Health check ALB (sin autenticación)
  GET  /health/                      → Alias
  GET  /fastapi/health               → Health check API-level
  POST /fastapi/empresas/            → Crear empresa   [requiere JWT]
  GET  /fastapi/empresas/            → Listar empresas [requiere JWT]
  GET  /fastapi/empresas/{id}        → Obtener empresa [requiere JWT]
  PUT  /fastapi/empresas/{id}        → Actualizar empresa [requiere JWT]
  DELETE /fastapi/empresas/{id}      → Eliminar empresa [requiere JWT]

Variables de entorno:
  AUTH0_DOMAIN        : tenant Auth0 (default: dev-qcbziogvv5h4151u.us.auth0.com)
  AUTH0_AUDIENCE      : API audience (default: https://measurements/api)
  AWS_REGION          : región AWS (default: us-east-1)
  DYNAMODB_ENDPOINT   : URL de DynamoDB Local (ej. http://10.0.1.5:8000)
                        Si no se define, usa DynamoDB real de AWS.
  CLOUDWATCH_LOG_GROUP: log group CloudWatch (default: /arquisoft/fastapi/security)
  CLOUDWATCH_LOG_STREAM: log stream (default: security-audit)
  FASTAPI_DEBUG       : True/False (default: False)
"""

import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Optional

import boto3
import jwt as pyjwt
import requests as http_requests
from botocore.exceptions import ClientError, NoCredentialsError, NoRegionError
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.middleware.base import BaseHTTPMiddleware

# ---------------------------------------------------------------------------
# Configuración — Variables de entorno
# ---------------------------------------------------------------------------
AUTH0_DOMAIN      = os.getenv("AUTH0_DOMAIN",      "dev-qcbziogvv5h4151u.us.auth0.com")
AUTH0_AUDIENCE    = os.getenv("AUTH0_AUDIENCE",    "https://measurements/api")
AWS_REGION        = os.getenv("AWS_REGION",        "us-east-1")
DYNAMODB_ENDPOINT = os.getenv("DYNAMODB_ENDPOINT", None)   # None → DynamoDB real AWS
CW_LOG_GROUP      = os.getenv("CLOUDWATCH_LOG_GROUP",  "/arquisoft/fastapi/security")
CW_LOG_STREAM     = os.getenv("CLOUDWATCH_LOG_STREAM", "security-audit")
DEBUG             = os.getenv("FASTAPI_DEBUG", "False").lower() == "true"

logging.basicConfig(
    level=logging.DEBUG if DEBUG else logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("empresas")

# Rutas públicas — no requieren JWT
_PUBLIC_PATHS = frozenset([
    "/health", "/health/",
    "/fastapi/health", "/fastapi/health/",
])

# ---------------------------------------------------------------------------
# Cache JWKS (claves públicas Auth0 — se refrescan cada hora)
# ---------------------------------------------------------------------------
_JWKS_CACHE: dict = {"keys": None, "expires_at": 0.0}
_JWKS_TTL = 3600  # segundos


# ---------------------------------------------------------------------------
# CloudWatch Audit Logger (ASR-10)
# ---------------------------------------------------------------------------
class CloudWatchAuditLogger:
    """
    Escribe eventos de seguridad inmutables en CloudWatch Logs (ASR-10).
    Si CloudWatch no está disponible (sin credenciales IAM), hace fallback
    al logger local sin interrumpir el flujo principal.
    """

    def __init__(self) -> None:
        self.client = boto3.client("logs", region_name=AWS_REGION)
        self.log_group = CW_LOG_GROUP
        self.log_stream = CW_LOG_STREAM
        self._sequence_token: Optional[str] = None
        self._ensure_stream()

    def log_security_event(
        self, event_type: str, user_email: str, ip: str, action: str
    ) -> None:
        entry = json.dumps({
            "event_type": event_type,
            "user":        user_email,
            "ip":          ip,
            "action":      action,
            "timestamp_ms": int(time.time() * 1000),
        })
        try:
            self._put(entry)
        except Exception as exc:
            logger.error("CloudWatch no disponible — log local: %s | Error: %s", entry, exc)

    def _put(self, message: str) -> None:
        kwargs: dict = {
            "logGroupName":  self.log_group,
            "logStreamName": self.log_stream,
            "logEvents": [{"timestamp": int(time.time() * 1000), "message": message}],
        }
        if self._sequence_token:
            kwargs["sequenceToken"] = self._sequence_token
        try:
            resp = self.client.put_log_events(**kwargs)
            self._sequence_token = resp.get("nextSequenceToken")
        except (NoCredentialsError, NoRegionError):
            raise
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code in ("InvalidSequenceTokenException", "DataAlreadyAcceptedException"):
                self._sequence_token = exc.response["Error"].get("expectedSequenceToken")
                if self._sequence_token:
                    self._put(message)
            else:
                raise

    def _ensure_stream(self) -> None:
        """Crea el log stream si no existe (idempotente)."""
        try:
            self.client.create_log_stream(
                logGroupName=self.log_group,
                logStreamName=self.log_stream,
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceAlreadyExistsException":
                logger.warning("No se pudo crear log stream: %s", exc)
        except (NoCredentialsError, NoRegionError) as exc:
            logger.warning("CloudWatch no disponible (sin credenciales IAM): %s", exc)


# Instancia global del logger (se comparte entre middleware y controladores)
_audit_logger: Optional[CloudWatchAuditLogger] = None


def get_audit_logger() -> CloudWatchAuditLogger:
    global _audit_logger
    if _audit_logger is None:
        _audit_logger = CloudWatchAuditLogger()
    return _audit_logger


# ---------------------------------------------------------------------------
# JWT Validation — Auth0 (ASR-10)
# ---------------------------------------------------------------------------
def _get_jwks() -> dict:
    """Obtiene JWKS de Auth0 con caché en memoria (1 hora)."""
    now = time.time()
    if _JWKS_CACHE["keys"] and now < _JWKS_CACHE["expires_at"]:
        return _JWKS_CACHE["keys"]
    url = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"
    resp = http_requests.get(url, timeout=5)
    resp.raise_for_status()
    jwks = resp.json()
    _JWKS_CACHE["keys"] = jwks
    _JWKS_CACHE["expires_at"] = now + _JWKS_TTL
    return jwks


def validate_jwt(token: str) -> dict:
    """
    Valida el JWT usando las claves públicas JWKS de Auth0.
    Lanza:
      jwt.ExpiredSignatureError  → token expirado
      jwt.InvalidAudienceError   → audience no coincide
      jwt.InvalidIssuerError     → issuer no coincide
      jwt.InvalidTokenError      → firma inválida u otro problema
    """
    jwks = _get_jwks()
    unverified_header = pyjwt.get_unverified_header(token)
    kid = unverified_header.get("kid")

    rsa_key: dict = {}
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            rsa_key = {
                "kty": key["kty"], "kid": key["kid"],
                "use": key["use"], "n": key["n"], "e": key["e"],
            }
            break

    if not rsa_key:
        raise pyjwt.InvalidTokenError("kid no encontrado en JWKS")

    public_key = pyjwt.algorithms.RSAAlgorithm.from_jwk(rsa_key)
    return pyjwt.decode(
        token,
        key=public_key,
        algorithms=["RS256"],
        audience=AUTH0_AUDIENCE,
        issuer=f"https://{AUTH0_DOMAIN}/",
    )


# ---------------------------------------------------------------------------
# Objeto usuario autenticado — inyectado en request.state.user
# ---------------------------------------------------------------------------
@dataclass
class AuthenticatedUser:
    email:      str
    empresa_id: Optional[str]
    roles:      list = field(default_factory=list)
    sub:        str = ""


# ---------------------------------------------------------------------------
# Security Middleware — ASR-10
# ---------------------------------------------------------------------------
class Auth0SecurityMiddleware(BaseHTTPMiddleware):
    """
    Primera capa de procesamiento de cada request en el Microservicio Empresas.

    Garantías (ASR-10):
      - 100 % de requests sin JWT válido retornan 401 sin ejecutar lógica de negocio
      - Cada rechazo se registra en CloudWatch con IP origen y timestamp
      - El JWT nunca se persiste: existe solo en memoria durante la request
    """

    async def dispatch(self, request: Request, call_next):
        # Rutas públicas — no requieren autenticación
        if request.url.path in _PUBLIC_PATHS:
            return await call_next(request)

        ip = request.client.host if request.client else "unknown"
        auth_header = request.headers.get("Authorization", "")

        # 1. Verificar presencia del header Authorization: Bearer <token>
        if not auth_header or not auth_header.startswith("Bearer "):
            return self._reject(
                ip=ip,
                reason="Token ausente o malformado",
                path=request.url.path,
            )

        # 2. Extraer token (SOLO en memoria — nunca se persiste)
        token = auth_header.split(" ", 1)[1]

        # 3. Validar JWT con Auth0
        try:
            payload = validate_jwt(token)
        except pyjwt.ExpiredSignatureError:
            return self._reject(ip, "Token expirado", request.url.path)
        except pyjwt.InvalidAudienceError:
            return self._reject(ip, "Audience inválida", request.url.path)
        except pyjwt.InvalidIssuerError:
            return self._reject(ip, "Issuer inválido", request.url.path)
        except Exception as exc:
            logger.warning("JWT inválido desde IP %s: %s", ip, exc)
            return self._reject(ip, f"JWT inválido: {type(exc).__name__}", request.url.path)

        # 4. Extraer claims y poblar request.state.user
        email      = payload.get("email") or payload.get(f"{AUTH0_DOMAIN}/email", "")
        empresa_id = payload.get("https://aqsf.com/empresa_id") or payload.get("empresa_id")
        roles      = payload.get("https://aqsf.com/roles", [])

        request.state.user = AuthenticatedUser(
            email=email,
            empresa_id=empresa_id,
            roles=roles,
            sub=payload.get("sub", ""),
        )

        # 5. Log de acceso autorizado (auditoría — ASR-10)
        get_audit_logger().log_security_event(
            event_type="ACCESO_AUTORIZADO",
            user_email=email,
            ip=ip,
            action=f"{request.method} {request.url.path}",
        )

        # Token sale de memoria aquí — no se persiste ✅
        del token

        return await call_next(request)

    @staticmethod
    def _reject(ip: str, reason: str, path: str) -> JSONResponse:
        """
        Bloquea la solicitud y registra evidencia inmutable en CloudWatch (ASR-10).
        Log incluye: timestamp, IP, recurso solicitado y razón del bloqueo.
        """
        get_audit_logger().log_security_event(
            event_type="ACCESO_BLOQUEADO",
            user_email="anonymous",
            ip=ip,
            action=f"Bloqueado en {path} — Razón: {reason}",
        )
        return JSONResponse(
            {"error": "No autorizado", "detail": reason},
            status_code=status.HTTP_401_UNAUTHORIZED,
        )


# ---------------------------------------------------------------------------
# DynamoDB client factory
# ---------------------------------------------------------------------------
def _get_dynamodb_resource():
    """
    Retorna un resource de DynamoDB.
    - Si DYNAMODB_ENDPOINT está definido → DynamoDB Local (credenciales dummy)
    - Si no → DynamoDB real de AWS (usa IAM Role del EC2)
    """
    kwargs: dict = {"region_name": AWS_REGION}
    if DYNAMODB_ENDPOINT:
        kwargs["endpoint_url"]          = DYNAMODB_ENDPOINT
        kwargs["aws_access_key_id"]     = "fakeMyKeyId"       # DynamoDB Local no verifica credenciales
        kwargs["aws_secret_access_key"] = "fakeSecretAccessKey"
    return boto3.resource("dynamodb", **kwargs)


def _ensure_empresa_table() -> None:
    """
    Crea la tabla 'Empresa' en DynamoDB si no existe.
    Operación idempotente — si ya existe, no hace nada.
    """
    dynamodb = _get_dynamodb_resource()
    try:
        table = dynamodb.create_table(
            TableName="Empresa",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        table.wait_until_exists()
        logger.info("Tabla 'Empresa' creada en DynamoDB")
    except ClientError as exc:
        if exc.response["Error"]["Code"] in (
            "ResourceInUseException", "TableAlreadyExistsException"
        ):
            logger.info("Tabla 'Empresa' ya existe en DynamoDB")
        else:
            logger.error("Error creando tabla 'Empresa': %s", exc)
    except (NoCredentialsError, NoRegionError) as exc:
        logger.warning("DynamoDB no disponible al inicio: %s", exc)


# ---------------------------------------------------------------------------
# Pydantic Schemas
# ---------------------------------------------------------------------------
class EmpresaCreate(BaseModel):
    nombre:            str
    nit:               str
    responsable_email: Optional[str] = None


class EmpresaUpdate(BaseModel):
    nombre:            Optional[str] = None
    nit:               Optional[str] = None
    responsable_email: Optional[str] = None


class EmpresaResponse(BaseModel):
    id:                str
    nombre:            str
    nit:               str
    responsable_email: Optional[str] = None
    creado_en:         str


# ---------------------------------------------------------------------------
# FastAPI App + Lifespan
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Inicialización y cierre del servicio."""
    logger.info("=== Microservicio Empresas iniciando (puerto 8001) ===")
    _ensure_empresa_table()
    # Inicializar audit logger al arranque para detectar problemas de credenciales
    try:
        get_audit_logger()
    except Exception as exc:
        logger.warning("CloudWatch audit logger no disponible al inicio: %s", exc)
    yield
    logger.info("=== Microservicio Empresas detenido ===")


app = FastAPI(
    title="Microservicio Empresas — AQSF",
    description=(
        "Gestión de empresas cliente con autenticación Auth0 JWT (ASR-10). "
        "Todos los endpoints — excepto /health — requieren Bearer token válido."
    ),
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/fastapi/docs" if DEBUG else None,
    redoc_url="/fastapi/redoc" if DEBUG else None,
)

# Registrar middleware de seguridad (primera capa — ASR-10)
app.add_middleware(Auth0SecurityMiddleware)


# ---------------------------------------------------------------------------
# Health Endpoints — sin autenticación (necesario para ALB health checks)
# ---------------------------------------------------------------------------
@app.get("/health", include_in_schema=False)
@app.get("/health/", include_in_schema=False)
@app.get("/fastapi/health", tags=["Health"])
@app.get("/fastapi/health/", include_in_schema=False)
def health_check():
    """Verificación de estado del servicio. No requiere autenticación."""
    return {"status": "ok", "service": "aqsf-empresas", "version": "1.0.0"}


# ---------------------------------------------------------------------------
# Endpoints de Empresas — todos requieren JWT válido (ASR-10)
# ---------------------------------------------------------------------------

@app.post(
    "/fastapi/empresas/",
    status_code=status.HTTP_201_CREATED,
    response_model=EmpresaResponse,
    tags=["Empresas"],
    summary="Crear empresa",
)
def crear_empresa(body: EmpresaCreate, request: Request):
    """
    Crea una nueva empresa cliente en DynamoDB.
    Requiere JWT válido de Auth0.
    """
    empresa_id = str(uuid.uuid4())
    creado_en  = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    item = {
        "id":                empresa_id,
        "nombre":            body.nombre,
        "nit":               body.nit,
        "responsable_email": body.responsable_email or "",
        "creado_en":         creado_en,
    }

    try:
        table = _get_dynamodb_resource().Table("Empresa")
        table.put_item(Item=item)
    except (NoCredentialsError, NoRegionError, ClientError) as exc:
        logger.error("Error guardando empresa en DynamoDB: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno al crear empresa",
        )

    user_email = _get_user_email(request)
    get_audit_logger().log_security_event(
        event_type="EMPRESA_CREADA",
        user_email=user_email,
        ip=_get_ip(request),
        action=f"Empresa creada — ID: {empresa_id}, Nombre: {body.nombre}, NIT: {body.nit}",
    )
    return item


@app.get(
    "/fastapi/empresas/",
    response_model=list[EmpresaResponse],
    tags=["Empresas"],
    summary="Listar empresas",
)
def listar_empresas(request: Request):
    """
    Lista todas las empresas registradas.
    Requiere JWT válido de Auth0.
    """
    try:
        table  = _get_dynamodb_resource().Table("Empresa")
        result = table.scan()
        return result.get("Items", [])
    except (NoCredentialsError, NoRegionError, ClientError) as exc:
        logger.error("Error listando empresas: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno al listar empresas",
        )


@app.get(
    "/fastapi/empresas/{empresa_id}",
    response_model=EmpresaResponse,
    tags=["Empresas"],
    summary="Obtener empresa por ID",
)
def obtener_empresa(empresa_id: str, request: Request):
    """
    Recupera una empresa por su UUID.
    Requiere JWT válido de Auth0.
    """
    try:
        table  = _get_dynamodb_resource().Table("Empresa")
        result = table.get_item(Key={"id": empresa_id})
        item   = result.get("Item")
    except (NoCredentialsError, NoRegionError, ClientError) as exc:
        logger.error("Error obteniendo empresa %s: %s", empresa_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno",
        )

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Empresa {empresa_id} no encontrada",
        )
    return item


@app.put(
    "/fastapi/empresas/{empresa_id}",
    response_model=EmpresaResponse,
    tags=["Empresas"],
    summary="Actualizar empresa",
)
def actualizar_empresa(empresa_id: str, body: EmpresaUpdate, request: Request):
    """
    Actualiza campos de una empresa existente.
    Requiere JWT válido de Auth0.
    """
    try:
        table  = _get_dynamodb_resource().Table("Empresa")
        result = table.get_item(Key={"id": empresa_id})
        item   = result.get("Item")
    except (NoCredentialsError, NoRegionError, ClientError) as exc:
        logger.error("Error buscando empresa %s para actualizar: %s", empresa_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno",
        )

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Empresa {empresa_id} no encontrada",
        )

    update_parts: list[str] = []
    expr_values:  dict      = {}

    if body.nombre is not None:
        update_parts.append("nombre = :n")
        expr_values[":n"] = body.nombre

    if body.nit is not None:
        update_parts.append("nit = :nit")
        expr_values[":nit"] = body.nit

    if body.responsable_email is not None:
        update_parts.append("responsable_email = :re")
        expr_values[":re"] = body.responsable_email

    if update_parts:
        try:
            table.update_item(
                Key={"id": empresa_id},
                UpdateExpression="SET " + ", ".join(update_parts),
                ExpressionAttributeValues=expr_values,
            )
        except (NoCredentialsError, NoRegionError, ClientError) as exc:
            logger.error("Error actualizando empresa %s: %s", empresa_id, exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Error interno al actualizar empresa",
            )

    # Retornar el item actualizado
    try:
        updated = table.get_item(Key={"id": empresa_id}).get("Item", item)
    except Exception:
        updated = item

    get_audit_logger().log_security_event(
        event_type="EMPRESA_ACTUALIZADA",
        user_email=_get_user_email(request),
        ip=_get_ip(request),
        action=f"Empresa {empresa_id} actualizada: {list(expr_values.keys())}",
    )
    return updated


@app.delete(
    "/fastapi/empresas/{empresa_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["Empresas"],
    summary="Eliminar empresa",
)
def eliminar_empresa(empresa_id: str, request: Request):
    """
    Elimina una empresa por su UUID.
    Requiere JWT válido de Auth0.
    """
    try:
        table  = _get_dynamodb_resource().Table("Empresa")
        result = table.get_item(Key={"id": empresa_id})
        if not result.get("Item"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Empresa {empresa_id} no encontrada",
            )
        table.delete_item(Key={"id": empresa_id})
    except HTTPException:
        raise
    except (NoCredentialsError, NoRegionError, ClientError) as exc:
        logger.error("Error eliminando empresa %s: %s", empresa_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno al eliminar empresa",
        )

    get_audit_logger().log_security_event(
        event_type="EMPRESA_ELIMINADA",
        user_email=_get_user_email(request),
        ip=_get_ip(request),
        action=f"Empresa {empresa_id} eliminada",
    )


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------
def _get_user_email(request: Request) -> str:
    """Extrae el email del usuario autenticado inyectado por el middleware."""
    user = getattr(request.state, "user", None)
    return getattr(user, "email", "unknown") if user else "unknown"


def _get_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"
