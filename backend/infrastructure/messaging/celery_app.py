"""
Celery Worker — Configuración y tareas asíncronas.

Broker: AWS SQS  (kombu[sqs])
Backend: No se usa result backend; los estados se persisten en PostgreSQL vía repositorios.

Tácticas implementadas:
  - Procesamiento asíncrono (ASR-9): la tarea se ejecuta sin bloquear el Core
  - Reintentos con backoff exponencial (ASR-9): hasta MAX_RETRIES intentos ante fallos transitorios
  - on_failure: notifica por SES al usuario si se agotan los reintentos (ASR-9)
"""

import logging
import os

import django
from celery import Celery, Task

from config.settings.env import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuración del broker SQS
# ---------------------------------------------------------------------------

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.django_settings")
django.setup()

app = Celery("aqsf_tasks")

app.conf.update(
    # Broker: SQS — las credenciales vienen del IAM Role del EC2 (ASR-10)
    broker_url=f"sqs://",
    broker_transport_options={
        "region": settings.AWS_REGION,
        "predefined_queues": {
            settings.AWS_SQS_QUEUE_NAME: {
                "url": settings.AWS_SQS_URL,
            }
        },
        # Polling: esperar hasta 20s por mensajes nuevos (long-polling SQS)
        "wait_time_seconds": 20,
        # Visibilidad: tiempo que el Worker tiene para procesar un mensaje
        "visibility_timeout": 3600,
    },
    # Sin result backend — los estados se persisten directamente en PostgreSQL
    task_ignore_result=True,
    # Formato de serialización
    task_serializer="json",
    accept_content=["json"],
    # Reintentos globales
    task_acks_late=True,          # Confirmar SOLO al completar exitosamente
    task_reject_on_worker_lost=True,
    # Concurrencia: ajustar según CPU del EC2 Celery (2GB RAM)
    worker_concurrency=4,
    worker_prefetch_multiplier=1,
)


# ---------------------------------------------------------------------------
# Clase base con manejo de fallos definitivos
# ---------------------------------------------------------------------------

class BaseTask(Task):
    """
    Clase base para todas las tareas AQSF.
    on_failure se invoca cuando se agotan todos los reintentos (ASR-9).
    """

    def on_failure(self, exc, task_id, args, kwargs, einfo):
        payload = args[0] if args else kwargs.get("payload", {})
        user_email = payload.get("user_email", "")
        analisis_id = payload.get("analisis_id", task_id)

        logger.error(
            "Tarea %s falló definitivamente. AnalisisId=%s User=%s Error=%s",
            task_id, analisis_id, user_email, exc,
        )

        # Notificar al usuario que el análisis falló (ASR-9)
        if user_email:
            try:
                from infrastructure.aws_services.ses_adapter import SESEmailAdapter
                ses = SESEmailAdapter()
                subject, body = SESEmailAdapter.build_error_email(
                    analisis_id=analisis_id,
                    empresa_nombre=payload.get("empresa_id", "desconocida"),
                    error_msg=str(exc),
                )
                ses.send_email(to=user_email, subject=subject, body=body)
            except Exception as mail_exc:
                logger.error("No se pudo enviar correo de error: %s", mail_exc)

        # Registrar en CloudWatch (ASR-10)
        try:
            from infrastructure.aws_services.adapters import CloudWatchAuditLogger
            audit = CloudWatchAuditLogger()
            audit.log_security_event(
                event_type="ANALISIS_FALLIDO",
                user_email=user_email or "desconocido",
                ip="worker-interno",
                action=f"Análisis {analisis_id} falló definitivamente: {exc}",
            )
        except Exception as log_exc:
            logger.error("No se pudo registrar fallo en CloudWatch: %s", log_exc)


# ---------------------------------------------------------------------------
# Tarea principal: ejecutar análisis de consumo cloud
# ---------------------------------------------------------------------------

@app.task(
    base=BaseTask,
    bind=True,
    name="analisis_optimizacion.worker",
    max_retries=settings.CELERY_TASK_MAX_RETRIES,
    # Backoff exponencial: 2s, 4s, 8s
    default_retry_delay=settings.CELERY_TASK_RETRY_BACKOFF,
)
def ejecutar_analisis_bg(self, payload: dict):
    """
    Tarea Celery que ejecuta el análisis de consumo cloud en background.

    payload esperado:
      {
        "analisis_id": str,
        "empresa_id":  str,
        "user_email":  str
      }

    ASR-9: Se reintenta hasta MAX_RETRIES veces con backoff exponencial.
    ASR-11: Calcula hash SHA-256 del reporte y lo persiste.
    """
    analisis_id = payload.get("analisis_id")
    empresa_id  = payload.get("empresa_id")
    user_email  = payload.get("user_email", "")

    logger.info(
        "Worker: iniciando análisis. AnalisisId=%s EmpresaId=%s User=%s",
        analisis_id, empresa_id, user_email,
    )

    try:
        # Construir dependencias (inyección manual)
        from infrastructure.database.repositories import DjangoAnalisisRepository, DjangoUnitOfWork
        from infrastructure.aws_services.ses_adapter import SESEmailAdapter
        from infrastructure.aws_services.adapters import CloudWatchAuditLogger
        from infrastructure.aws_services.cloud_provider_adapter import CloudWatchMetricsAdapter
        from application.analisis_optimizacion.worker_use_cases import ProcesarAnalisisUseCase

        use_case = ProcesarAnalisisUseCase(
            analisis_repo=DjangoAnalisisRepository(),
            notification_service=SESEmailAdapter(),
            audit_logger=CloudWatchAuditLogger(),
            cloud_client=CloudWatchMetricsAdapter(),
            frontend_url=settings.FRONTEND_URL,
        )

        result = use_case.execute(
            analisis_id=analisis_id,
            empresa_id=empresa_id,
            user_email=user_email,
        )
        logger.info("Worker: análisis completado. Resultado=%s", result)
        return result

    except Exception as exc:
        # Reintento con backoff exponencial (ASR-9)
        retry_delay = settings.CELERY_TASK_RETRY_BACKOFF ** (self.request.retries + 1)
        logger.warning(
            "Worker: error en intento %d/%d. Reintentando en %ds. Error: %s",
            self.request.retries + 1,
            settings.CELERY_TASK_MAX_RETRIES,
            retry_delay,
            exc,
        )
        raise self.retry(exc=exc, countdown=retry_delay)

