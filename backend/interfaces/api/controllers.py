"""
Controladores REST — Capa de Interfaces.

AnalisisController  → POST /api/analisis/
    Encola el análisis y retorna 202 inmediatamente (ASR-9).
    El middleware de seguridad ya validó el token y pobló request.user (ASR-10).

ReporteController   → GET /api/reportes/<analisis_id>/
    Recupera el reporte, verifica integridad SHA-256 (ASR-11) y lo retorna.
"""

import logging

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from application.analisis_optimizacion.use_cases import EjecutarAnalisisUseCase
from application.analisis_optimizacion.dtos import AnalisisRequestDTO
from infrastructure.database.repositories import DjangoAnalisisRepository, DjangoUnitOfWork
from infrastructure.aws_services.adapters import SQSPublisherAdapter, CloudWatchAuditLogger
from infrastructure.aws_services.ses_adapter import SESEmailAdapter
from infrastructure.aws_services.cloud_provider_adapter import CloudWatchMetricsAdapter
from application.analisis_optimizacion.worker_use_cases import VerificarIntegridadUseCase
from config.settings.env import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Factory de dependencias (DI manual sin framework externo)
# ---------------------------------------------------------------------------

def _build_ejecutar_analisis_use_case() -> EjecutarAnalisisUseCase:
    """Construye EjecutarAnalisisUseCase con todas sus dependencias reales."""
    return EjecutarAnalisisUseCase(
        uow=DjangoUnitOfWork(),
        analisis_repo=DjangoAnalisisRepository(),
        queue=SQSPublisherAdapter(),
        audit_logger=CloudWatchAuditLogger(),
    )


def _build_verificar_integridad_use_case() -> VerificarIntegridadUseCase:
    from infrastructure.database.models import EmpresaModel

    def get_responsable_email(empresa_id: str) -> str:
        try:
            empresa = EmpresaModel.objects.get(id=empresa_id)
            return empresa.responsable_email or ""
        except EmpresaModel.DoesNotExist:
            return ""

    return VerificarIntegridadUseCase(
        analisis_repo=DjangoAnalisisRepository(),
        notification_service=SESEmailAdapter(),
        audit_logger=CloudWatchAuditLogger(),
        responsable_email_fn=get_responsable_email,
    )


# ---------------------------------------------------------------------------
# Controladores
# ---------------------------------------------------------------------------

class AnalisisController(APIView):
    """
    POST /api/analisis/
    Body: { "empresa_id": str, "tipo_analisis": str }

    Retorna 202 Accepted inmediatamente con { analisis_id, estado: "PENDIENTE" }.
    El Worker Celery procesa en background y notifica por correo al finalizar (ASR-9).
    """

    def post(self, request):
        empresa_id   = request.data.get("empresa_id", "").strip()
        tipo_analisis = request.data.get("tipo_analisis", "").strip()

        if not empresa_id or not tipo_analisis:
            return Response(
                {"error": "empresa_id y tipo_analisis son requeridos"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # request.user.email inyectado por Auth0SecurityMiddleware (ASR-10)
        user_email = getattr(request.user, "email", "unknown@domain.com")

        # Verificar que la empresa del token coincida con la solicitada (tenant isolation — ASR-10)
        user_empresa_id = getattr(request.user, "empresa_id", None)
        if user_empresa_id and str(user_empresa_id) != empresa_id:
            logger.warning(
                "Intento de acceso cruzado: user_empresa=%s solicitado=%s user=%s",
                user_empresa_id, empresa_id, user_email,
            )
            CloudWatchAuditLogger().log_security_event(
                event_type="ACCESO_CRUZADO_BLOQUEADO",
                user_email=user_email,
                ip=request.META.get("REMOTE_ADDR", ""),
                action=f"Intento de analizar empresa {empresa_id} sin autorización",
            )
            return Response(
                {"error": "No autorizado para acceder a datos de esta empresa"},
                status=status.HTTP_403_FORBIDDEN,
            )

        dto = AnalisisRequestDTO(
            empresa_id=empresa_id,
            tipo_analisis=tipo_analisis,
            requested_by_email=user_email,
        )

        try:
            use_case = _build_ejecutar_analisis_use_case()
            response_dto = use_case.execute(dto)
            return Response(
                {
                    **response_dto.model_dump(),
                    "mensaje": "Análisis encolado exitosamente. Se le notificará por correo al finalizar.",
                },
                status=status.HTTP_202_ACCEPTED,
            )
        except Exception as exc:
            logger.error("Error al encolar análisis: %s", exc)
            return Response(
                {"error": "Error interno al encolar el análisis"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class ReporteController(APIView):
    """
    GET /api/reportes/<analisis_id>/

    Recupera el reporte, verifica integridad SHA-256 (ASR-11) y lo retorna.
    Si el hash no coincide, genera alerta y devuelve 409 Conflict.
    """

    def get(self, request, analisis_id: str):
        import json
        from infrastructure.database.models import AnalisisConsumoModel

        # Verificar que el usuario tiene acceso al reporte (ASR-10)
        user_empresa_id = getattr(request.user, "empresa_id", None)

        try:
            model = AnalisisConsumoModel.objects.get(id=analisis_id)
        except AnalisisConsumoModel.DoesNotExist:
            return Response({"error": "Reporte no encontrado"}, status=status.HTTP_404_NOT_FOUND)

        if user_empresa_id and str(model.empresa_id) != str(user_empresa_id):
            CloudWatchAuditLogger().log_security_event(
                event_type="ACCESO_NO_AUTORIZADO",
                user_email=getattr(request.user, "email", ""),
                ip=request.META.get("REMOTE_ADDR", ""),
                action=f"Intento de acceder a reporte {analisis_id} de otra empresa",
            )
            return Response({"error": "No autorizado"}, status=status.HTTP_403_FORBIDDEN)

        reporte = {
            "analisis_id": str(model.id),
            "empresa_id": str(model.empresa_id),
            "tipo_analisis": model.tipo_analisis,
            "estado": model.estado,
            "creado_en": model.creado_en.isoformat() if model.creado_en else None,
            "completado_en": model.completado_en.isoformat() if model.completado_en else None,
        }

        # Verificar integridad (ASR-11)
        if model.report_hash and model.estado == "COMPLETADO":
            use_case = _build_verificar_integridad_use_case()
            integro = use_case.execute(analisis_id=analisis_id, report_content=reporte)
            reporte["integridad_verificada"] = integro
            if not integro:
                return Response(
                    {
                        **reporte,
                        "alerta": "⚠️ La integridad del reporte está comprometida. Se ha notificado al responsable.",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

        return Response(reporte, status=status.HTTP_200_OK)
