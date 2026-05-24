"""
Controlador de Integridad — ASR-11

Endpoints:
  GET  /api/reportes/<id>/verify/         → Verificar integridad SHA-256 sin exponer contenido
  POST /api/test/integrity-breach/<id>/   → Simular corrupción de hash (solo DEBUG)
  POST /api/test/write-rejection/         → Probar rechazo de escritura sobre AWS (solo DEBUG)

Los endpoints /api/test/* SOLO están disponibles cuando DEBUG=True en settings.
En producción devuelven 404.
"""

import hashlib
import json
import logging
import time

from django.conf import settings
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from infrastructure.database.models import AnalisisConsumoModel, EmpresaModel
from infrastructure.database.repositories import DjangoAnalisisRepository
from infrastructure.aws_services.adapters import CloudWatchAuditLogger
from infrastructure.aws_services.ses_adapter import SESEmailAdapter
from infrastructure.aws_services.cloud_provider_adapter import CloudWatchMetricsAdapter
from application.analisis_optimizacion.worker_use_cases import VerificarIntegridadUseCase
from application.analisis_optimizacion.anomaly_detection import AnomalyDetector

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers de DI
# ---------------------------------------------------------------------------

def _get_responsable_email(empresa_id: str) -> str:
    try:
        empresa = EmpresaModel.objects.get(id=empresa_id)
        return empresa.responsable_email or ""
    except EmpresaModel.DoesNotExist:
        return ""


def _build_verificar_use_case() -> VerificarIntegridadUseCase:
    return VerificarIntegridadUseCase(
        analisis_repo=DjangoAnalisisRepository(),
        notification_service=SESEmailAdapter(),
        audit_logger=CloudWatchAuditLogger(),
        responsable_email_fn=_get_responsable_email,
    )


# ---------------------------------------------------------------------------
# Endpoint de verificación de integridad (producción)
# ---------------------------------------------------------------------------

class IntegrityVerifyController(APIView):
    """
    GET /api/reportes/<analisis_id>/verify/

    Verifica la integridad SHA-256 del reporte sin exponer su contenido completo.
    Útil para que el cliente confirme la integridad antes de procesar el reporte.

    Respuestas:
      200 { integro: true,  hash_almacenado: "...", verificado_en: "..." }
      409 { integro: false, alerta: "...", hash_almacenado: "...", hash_actual: "..." }
      404 Reporte no encontrado
    """

    def get(self, request, analisis_id: str):
        user_empresa_id = getattr(request.user, "empresa_id", None)

        try:
            model = AnalisisConsumoModel.objects.get(id=analisis_id)
        except AnalisisConsumoModel.DoesNotExist:
            return Response({"error": "Reporte no encontrado"}, status=status.HTTP_404_NOT_FOUND)

        # Control de acceso por tenant (ASR-10)
        if user_empresa_id and str(model.empresa_id) != str(user_empresa_id):
            CloudWatchAuditLogger().log_security_event(
                event_type="ACCESO_NO_AUTORIZADO",
                user_email=getattr(request.user, "email", ""),
                ip=request.META.get("REMOTE_ADDR", ""),
                action=f"Intento de verificar integridad de reporte {analisis_id} de otra empresa",
            )
            return Response({"error": "No autorizado"}, status=status.HTTP_403_FORBIDDEN)

        if model.estado != "COMPLETADO" or not model.report_hash:
            return Response(
                {
                    "integro": None,
                    "mensaje": f"El reporte está en estado '{model.estado}', aún no tiene hash.",
                },
                status=status.HTTP_200_OK,
            )

        # Reconstruir el contenido del reporte para recalcular hash
        report_content = {
            "analisis_id": str(model.id),
            "empresa_id":  str(model.empresa_id),
            "tipo_analisis": model.tipo_analisis,
            "estado": model.estado,
            "creado_en":    model.creado_en.isoformat() if model.creado_en else None,
            "completado_en": model.completado_en.isoformat() if model.completado_en else None,
        }

        t_inicio = time.time()
        use_case = _build_verificar_use_case()
        integro  = use_case.execute(analisis_id=analisis_id, report_content=report_content)
        t_deteccion_ms = int((time.time() - t_inicio) * 1000)

        if integro:
            return Response(
                {
                    "integro": True,
                    "hash_almacenado": model.report_hash,
                    "verificado_en": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "tiempo_verificacion_ms": t_deteccion_ms,
                },
                status=status.HTTP_200_OK,
            )

        # Calcular hash actual para evidencia
        content_str  = json.dumps(report_content, sort_keys=True, ensure_ascii=False)
        current_hash = hashlib.sha256(content_str.encode("utf-8")).hexdigest()

        return Response(
            {
                "integro": False,
                "alerta": "⚠️ Integridad comprometida. El responsable fue notificado.",
                "hash_almacenado": model.report_hash,
                "hash_actual":     current_hash,
                "tiempo_deteccion_ms": t_deteccion_ms,
                "asr11_cumplido": t_deteccion_ms < 60_000,  # < 60 segundos
            },
            status=status.HTTP_409_CONFLICT,
        )


# ---------------------------------------------------------------------------
# Endpoints de Testing — SOLO disponibles en DEBUG (ASR-11 testing)
# ---------------------------------------------------------------------------

class IntegrityBreachSimulatorController(APIView):
    """
    POST /api/test/integrity-breach/<analisis_id>/

    Corrompe el hash SHA-256 almacenado de un reporte para simular una
    alteración de datos. SOLO disponible en DEBUG=True.

    Permite que JMeter valide el flujo completo de detección de integridad
    sin necesidad de acceder directamente a la BD.

    Body (opcional):
      { "modo": "hash_invalido" | "hash_parcial" | "hash_aleatorio" }
    """

    def post(self, request, analisis_id: str):
        if not settings.DEBUG:
            return Response({"error": "No encontrado"}, status=status.HTTP_404_NOT_FOUND)

        modo = request.data.get("modo", "hash_invalido")

        try:
            model = AnalisisConsumoModel.objects.get(id=analisis_id)
        except AnalisisConsumoModel.DoesNotExist:
            return Response({"error": "Análisis no encontrado"}, status=status.HTTP_404_NOT_FOUND)

        if model.estado != "COMPLETADO" or not model.report_hash:
            return Response(
                {"error": "El análisis no está completado o no tiene hash"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        hash_original = model.report_hash

        # Corromper el hash según el modo
        if modo == "hash_invalido":
            # Hash completamente falso (64 chars de 'f')
            hash_corrupto = "f" * 64
        elif modo == "hash_parcial":
            # Modificar los primeros 4 caracteres del hash original
            hash_corrupto = "dead" + hash_original[4:]
        else:
            # Hash aleatorio
            import os
            hash_corrupto = hashlib.sha256(os.urandom(32)).hexdigest()

        model.report_hash = hash_corrupto
        model.save(update_fields=["report_hash"])

        # Registrar la simulación en CloudWatch para trazabilidad
        CloudWatchAuditLogger().log_security_event(
            event_type="SIMULACION_BRECHA_INTEGRIDAD",
            user_email=getattr(request.user, "email", "test-runner"),
            ip=request.META.get("REMOTE_ADDR", ""),
            action=f"Hash corrompido en análisis {analisis_id} para prueba ASR-11. Modo={modo}",
        )

        logger.info(
            "Hash corrompido para testing. AnalisisId=%s Original=%s... Corrupto=%s...",
            analisis_id, hash_original[:8], hash_corrupto[:8],
        )

        return Response(
            {
                "mensaje": "Hash corrompido exitosamente para prueba de integridad",
                "analisis_id": analisis_id,
                "hash_original_preview": hash_original[:16] + "...",
                "hash_corrupto_preview": hash_corrupto[:16] + "...",
                "siguiente_paso": f"GET /api/reportes/{analisis_id}/verify/ para detectar la alteración",
            },
            status=status.HTTP_200_OK,
        )


class WriteRejectionTestController(APIView):
    """
    POST /api/test/write-rejection/

    Verifica que el CloudWatchMetricsAdapter rechaza operaciones de escritura
    sobre APIs de AWS (ASR-11: el sistema opera en modo solo lectura).

    Body:
      { "operacion": "put_metric_data" | "create_alarm" | "delete_alarm" }
    """

    def post(self, request):
        if not settings.DEBUG:
            return Response({"error": "No encontrado"}, status=status.HTTP_404_NOT_FOUND)

        operacion = request.data.get("operacion", "put_metric_data")
        adapter   = CloudWatchMetricsAdapter()

        t_inicio = time.time()
        try:
            # Intentar una operación de escritura — debe ser rechazada
            adapter._reject_write_operation(operacion, context="test ASR-11")
            # Si llegamos aquí, la escritura NO fue rechazada → fallo de seguridad
            return Response(
                {
                    "rechazado": False,
                    "alerta": "⚠️ La operación de escritura NO fue rechazada. ASR-11 incumplido.",
                    "operacion": operacion,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        except PermissionError as exc:
            t_ms = int((time.time() - t_inicio) * 1000)
            return Response(
                {
                    "rechazado": True,
                    "mensaje": "✅ Operación de escritura rechazada correctamente (ASR-11)",
                    "operacion": operacion,
                    "error": str(exc),
                    "tiempo_ms": t_ms,
                    "log_generado": True,
                },
                status=status.HTTP_200_OK,
            )


class AnomalyStatusController(APIView):
    """
    GET /api/test/anomaly-status/<empresa_id>/

    Retorna el contador actual de alteraciones de integridad para una empresa
    en la ventana de tiempo activa. SOLO DEBUG.
    """

    def get(self, request, empresa_id: str):
        if not settings.DEBUG:
            return Response({"error": "No encontrado"}, status=status.HTTP_404_NOT_FOUND)

        from interfaces.middlewares.rate_limit_middleware import RateLimitStore
        from application.analisis_optimizacion.anomaly_detection import THRESHOLD, WINDOW_SECONDS

        store = RateLimitStore()
        key   = f"integrity:breach:{empresa_id}"
        count_raw = store.get(key)
        count = int(count_raw) if count_raw else 0

        return Response(
            {
                "empresa_id":          empresa_id,
                "alteraciones_activas": count,
                "umbral_anomalia":     THRESHOLD,
                "ventana_segundos":    WINDOW_SECONDS,
                "anomalia_activa":     count >= THRESHOLD,
            },
            status=status.HTTP_200_OK,
        )
