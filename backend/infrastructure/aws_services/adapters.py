"""
Adaptadores AWS principales:
  - SQSPublisherAdapter : encola tareas Celery en SQS (ASR-9)
  - CloudWatchAuditLogger: persiste logs inmutables de auditoría (ASR-10 / ASR-11)
"""

import json
import time
import logging

import boto3
from botocore.exceptions import ClientError, NoCredentialsError, NoRegionError

from core.shared.interfaces import ITaskQueue, IAuditLogger
from config.settings.env import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# SQS — Broker de tareas asíncronas
# ---------------------------------------------------------------------------

class SQSPublisherAdapter(ITaskQueue):
    """
    Publica mensajes en SQS para que el Celery Worker los consuma (ASR-9).
    Las credenciales provienen del IAM Role del EC2 — sin hardcodeo (ASR-10).
    """

    def __init__(self):
        self.client = boto3.client("sqs", region_name=settings.AWS_REGION)

    def enqueue_task(self, task_name: str, payload: dict) -> None:
        if not settings.AWS_SQS_URL:
            logger.warning("AWS_SQS_URL no configurada — modo MOCK. Tarea: %s", task_name)
            return

        message_body = json.dumps({"task": task_name, "payload": payload})
        try:
            response = self.client.send_message(
                QueueUrl=settings.AWS_SQS_URL,
                MessageBody=message_body,
            )
            logger.info(
                "Tarea encolada en SQS. Task=%s MessageId=%s",
                task_name,
                response.get("MessageId"),
            )
        except (NoCredentialsError, NoRegionError) as e:
            # IAM role no disponible — log y continúa (el 202 se preserva, el worker reintentará)
            logger.error("SQS sin credenciales IAM — tarea %s no encolada: %s", task_name, e)
        except ClientError as e:
            # Error de SQS (permisos, cola no existe, etc.) — log y continúa
            logger.error("Error SQS al encolar tarea %s: %s", task_name, e)
        except Exception as e:
            # Cualquier otro error de red/timeout — log y continúa
            logger.error("Error inesperado encolando tarea %s: %s", task_name, e)


# ---------------------------------------------------------------------------
# CloudWatch Logs — Auditoría inmutable
# ---------------------------------------------------------------------------

class CloudWatchAuditLogger(IAuditLogger):
    """
    Escribe eventos de seguridad en CloudWatch Logs (ASR-10 / ASR-11).

    El log group debe tener:
      - Política de recursos de solo escritura (no se puede borrar ni modificar)
      - Retención mínima de 90 días configurada en Terraform
    """

    def __init__(self):
        self.client = boto3.client("logs", region_name=settings.AWS_REGION)
        self.log_group = settings.CLOUDWATCH_LOG_GROUP
        self.log_stream = settings.CLOUDWATCH_LOG_STREAM
        self._sequence_token: str | None = None
        self._ensure_log_stream()

    # ------------------------------------------------------------------
    # Interfaz pública
    # ------------------------------------------------------------------

    def log_security_event(
        self, event_type: str, user_email: str, ip: str, action: str
    ) -> None:
        """
        Persiste un evento de auditoría inmutable en CloudWatch.
        Si falla (p. ej. sin conectividad), registra el error localmente
        pero NO interrumpe el flujo principal (fail-safe para auditoría).
        """
        log_entry = json.dumps(
            {
                "event_type": event_type,
                "user": user_email,
                "ip": ip,
                "action": action,
                "timestamp_ms": int(time.time() * 1000),
            }
        )
        try:
            self._put_log_event(log_entry)
        except Exception as exc:
            # Fallback: al menos queda en los logs del servidor
            logger.error(
                "CloudWatch no disponible — log local: %s | Error: %s",
                log_entry,
                exc,
            )

    # ------------------------------------------------------------------
    # Helpers internos
    # ------------------------------------------------------------------

    def _put_log_event(self, message: str) -> None:
        kwargs: dict = {
            "logGroupName": self.log_group,
            "logStreamName": self.log_stream,
            "logEvents": [{"timestamp": int(time.time() * 1000), "message": message}],
        }
        if self._sequence_token:
            kwargs["sequenceToken"] = self._sequence_token

        try:
            response = self.client.put_log_events(**kwargs)
            self._sequence_token = response.get("nextSequenceToken")
        except (NoCredentialsError, NoRegionError):
            raise
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            if error_code in ("InvalidSequenceTokenException", "DataAlreadyAcceptedException"):
                self._sequence_token = e.response["Error"].get("expectedSequenceToken")
                if self._sequence_token:
                    self._put_log_event(message)
            else:
                raise

    def _ensure_log_stream(self) -> None:
        """Crea el log stream si no existe (idempotente)."""
        try:
            self.client.create_log_stream(
                logGroupName=self.log_group,
                logStreamName=self.log_stream,
            )
        except ClientError as e:
            if e.response["Error"]["Code"] != "ResourceAlreadyExistsException":
                logger.warning("No se pudo crear log stream: %s", e)
        except (NoCredentialsError, NoRegionError) as e:
            logger.warning("CloudWatch no disponible (sin credenciales IAM): %s", e)
