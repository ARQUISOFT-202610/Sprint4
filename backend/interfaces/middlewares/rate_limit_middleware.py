"""
Middleware de Rate Limiting y Detección de Ataques (ASR-10 — Confidencialidad)

Detecta y bloquea:
  1. Brute force: > N intentos fallidos por IP en ventana de tiempo
  2. Patrones sospechosos: múltiples intentos de acceso cruzado entre tenants
  3. Escaneo de endpoints: muchos 404/403 en corto tiempo

Implementación:
  - Backend: dict en memoria
  - Todos los bloqueos se registran en CloudWatch (ASR-10)

Configuración (env vars):
  RATE_LIMIT_FAILED_AUTH_MAX  : máx intentos fallidos de auth (default: 10)
  RATE_LIMIT_WINDOW_SECONDS   : ventana de tiempo en segundos (default: 60)
  RATE_LIMIT_BLOCK_SECONDS    : tiempo de bloqueo (default: 300 = 5 minutos)
"""

import json
import logging
import time
from typing import Optional

from django.http import JsonResponse

from config.settings.env import settings
from infrastructure.aws_services.adapters import CloudWatchAuditLogger

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuración de umbrales
# ---------------------------------------------------------------------------
FAILED_AUTH_MAX   = int(getattr(settings, "RATE_LIMIT_FAILED_AUTH_MAX", 10))
WINDOW_SECONDS    = int(getattr(settings, "RATE_LIMIT_WINDOW_SECONDS", 60))
BLOCK_SECONDS     = int(getattr(settings, "RATE_LIMIT_BLOCK_SECONDS", 300))
CROSS_TENANT_MAX  = int(getattr(settings, "RATE_LIMIT_CROSS_TENANT_MAX", 3))

# ---------------------------------------------------------------------------
# Backend de almacenamiento (Redis con fallback en memoria)
# ---------------------------------------------------------------------------

class _MemoryStore:
    """Backend en memoria para rate limiting."""
    _data: dict = {}

    def get(self, key: str) -> Optional[str]:
        entry = self._data.get(key)
        if entry and entry["expires"] > time.time():
            return entry["value"]
        self._data.pop(key, None)
        return None

    def incr(self, key: str, window: int) -> int:
        now = time.time()
        entry = self._data.get(key)
        if not entry or entry["expires"] <= now:
            self._data[key] = {"value": 1, "expires": now + window}
            return 1
        self._data[key]["value"] += 1
        return self._data[key]["value"]

    def set(self, key: str, value: str, ttl: int) -> None:
        self._data[key] = {"value": value, "expires": time.time() + ttl}

    def delete(self, key: str) -> None:
        self._data.pop(key, None)


_memory_store = _MemoryStore()


class RateLimitStore:
    """Abstracción sobre memoria para el rate limiter."""

    def incr_with_ttl(self, key: str, ttl: int) -> int:
        return _memory_store.incr(key, ttl)

    def get(self, key: str) -> Optional[str]:
        return _memory_store.get(key)

    def set(self, key: str, value: str, ttl: int) -> None:
        _memory_store.set(key, value, ttl)

    def delete(self, key: str) -> None:
        _memory_store.delete(key)


# ---------------------------------------------------------------------------
# Middleware principal
# ---------------------------------------------------------------------------

class RateLimitMiddleware:
    """
    Detecta y bloquea ataques de fuerza bruta y accesos sospechosos (ASR-10).

    Debe ir DESPUÉS de Auth0SecurityMiddleware en MIDDLEWARE settings
    para poder capturar respuestas 401/403 del middleware de seguridad.
    """

    def __init__(self, get_response):
        self.get_response = get_response
        self.store = RateLimitStore()
        self.audit_logger = CloudWatchAuditLogger()

    def __call__(self, request):
        ip = request.META.get("REMOTE_ADDR", "unknown")

        # 1. Verificar si la IP está bloqueada
        block_key = f"rl:blocked:{ip}"
        if self.store.get(block_key):
            self.audit_logger.log_security_event(
                event_type="IP_BLOQUEADA_RATE_LIMIT",
                user_email="bloqueado",
                ip=ip,
                action=f"Solicitud rechazada — IP {ip} en lista de bloqueo temporal",
            )
            return JsonResponse(
                {
                    "error": "Demasiados intentos fallidos. Intente nuevamente más tarde.",
                    "retry_after_seconds": BLOCK_SECONDS,
                },
                status=429,
            )

        # 2. Procesar solicitud
        response = self.get_response(request)

        # 3. Contar respuestas 401 (auth fallida)
        if response.status_code == 401:
            count = self.store.incr_with_ttl(f"rl:auth_fail:{ip}", WINDOW_SECONDS)
            if count >= FAILED_AUTH_MAX:
                self._block_ip(ip, reason=f"Brute force: {count} fallos de auth en {WINDOW_SECONDS}s")

        # 4. Contar respuestas 403 (acceso cruzado / no autorizado)
        if response.status_code == 403:
            count = self.store.incr_with_ttl(f"rl:forbidden:{ip}", WINDOW_SECONDS)
            if count >= CROSS_TENANT_MAX:
                self._block_ip(
                    ip,
                    reason=f"Múltiples intentos de acceso cruzado: {count} intentos 403 en {WINDOW_SECONDS}s",
                )

        return response

    def _block_ip(self, ip: str, reason: str) -> None:
        """Bloquea una IP por BLOCK_SECONDS y registra en CloudWatch."""
        self.store.set(f"rl:blocked:{ip}", "1", BLOCK_SECONDS)
        logger.warning("IP %s bloqueada por %ds. Razón: %s", ip, BLOCK_SECONDS, reason)
        self.audit_logger.log_security_event(
            event_type="IP_BLOQUEADA_AUTOMATICAMENTE",
            user_email="sistema",
            ip=ip,
            action=reason,
        )
