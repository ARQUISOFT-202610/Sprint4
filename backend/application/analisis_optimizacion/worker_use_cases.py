"""
Casos de uso ejecutados por el Celery Worker (procesamiento en background).

ProcesarAnalisisUseCase  — ASR-9 (Disponibilidad) + ASR-11 (Integridad)
  1. Recupera el análisis de la BD y lo marca EN_PROGRESO
  2. Consulta datos de consumo cloud (solo lectura — ASR-11)
  3. Calcula hash SHA-256 del reporte (ASR-11)
  4. Persiste estado COMPLETADO + hash
  5. Notifica por correo al solicitante (ASR-9)

VerificarIntegridadUseCase — ASR-11
  1. Recupera reporte y hash almacenado
  2. Recalcula hash del contenido actual
  3. Si hay discrepancia → log en CloudWatch + alerta SES al responsable
"""

import hashlib
import json
import logging

from core.shared.interfaces import (
    IAnalisisRepository,
    INotificationService,
    IAuditLogger,
    ICloudProviderClient,
)
from infrastructure.aws_services.ses_adapter import SESEmailAdapter

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Caso de uso: Procesar análisis en background (Worker)
# ---------------------------------------------------------------------------

class ProcesarAnalisisUseCase:
    """
    Ejecutado por el Celery Worker al consumir una tarea de SQS.
    Implementa el lado asíncrono del flujo ASR-9.
    """

    def __init__(
        self,
        analisis_repo: IAnalisisRepository,
        notification_service: INotificationService,
        audit_logger: IAuditLogger,
        cloud_client: ICloudProviderClient,
        frontend_url: str,
    ):
        self.analisis_repo = analisis_repo
        self.notification_service = notification_service
        self.audit_logger = audit_logger
        self.cloud_client = cloud_client
        self.frontend_url = frontend_url

    def execute(self, analisis_id: str, empresa_id: str, user_email: str) -> dict:
        """
        Retorna dict con analisis_id, estado y hash al completar.
        Lanza excepción en caso de fallo para que Celery reintente.
        """
        # 1. Marcar como EN_PROGRESO
        analisis = self.analisis_repo.get_by_id(analisis_id)
        analisis.iniciar_ejecucion()
        self.analisis_repo.save(analisis)

        self.audit_logger.log_security_event(
            event_type="ANALISIS_INICIADO",
            user_email=user_email,
            ip="worker-interno",
            action=f"Worker inició procesamiento de análisis {analisis_id}",
        )

        try:
            # 2. Consultar datos de consumo cloud (SOLO LECTURA — ASR-11)
            usage_data = self.cloud_client.fetch_usage_data(empresa_id)

            # 3. Calcular hash SHA-256 del reporte (ASR-11: integridad)
            report_content = json.dumps(usage_data, sort_keys=True, ensure_ascii=False)
            report_hash = hashlib.sha256(report_content.encode("utf-8")).hexdigest()

            # 4. Completar análisis y persistir
            analisis.completar(report_hash=report_hash)
            if hasattr(analisis, "solicitado_por"):
                analisis.solicitado_por = user_email
            self.analisis_repo.save(analisis)

            # 5. Notificar éxito por correo (ASR-9)
            subject, body = SESEmailAdapter.build_success_email(
                analisis_id=analisis_id,
                empresa_nombre=usage_data.get("empresa_nombre", empresa_id),
                frontend_url=self.frontend_url,
            )
            self.notification_service.send_email(to=user_email, subject=subject, body=body)

            self.audit_logger.log_security_event(
                event_type="ANALISIS_COMPLETADO",
                user_email=user_email,
                ip="worker-interno",
                action=f"Análisis {analisis_id} completado. Hash={report_hash[:16]}...",
            )

            return {"analisis_id": analisis_id, "estado": "COMPLETADO", "hash": report_hash}

        except Exception as exc:
            # Marcar como FALLIDO para trazabilidad
            analisis.estado = "FALLIDO"
            self.analisis_repo.save(analisis)
            logger.error("Análisis %s falló: %s", analisis_id, exc)
            raise  # Celery captura y reintenta según BaseTask.on_failure


# ---------------------------------------------------------------------------
# Caso de uso: Verificar integridad de un reporte (ASR-11)
# ---------------------------------------------------------------------------

class VerificarIntegridadUseCase:
    """
    Verifica que el hash SHA-256 almacenado coincida con el contenido actual.
    Se ejecuta cada vez que se consulta un reporte (ASR-11).
    """

    def __init__(
        self,
        analisis_repo: IAnalisisRepository,
        notification_service: INotificationService,
        audit_logger: IAuditLogger,
        responsable_email_fn,  # callable(empresa_id) -> str
    ):
        self.analisis_repo = analisis_repo
        self.notification_service = notification_service
        self.audit_logger = audit_logger
        self.responsable_email_fn = responsable_email_fn

    def execute(self, analisis_id: str, report_content: dict) -> bool:
        """
        Retorna True si el reporte es íntegro, False si fue alterado.
        En caso de discrepancia: log inmutable + alerta por correo.
        """
        analisis = self.analisis_repo.get_by_id(analisis_id)

        if not analisis.report_hash:
            # Reporte sin hash no puede verificarse
            logger.warning("Análisis %s no tiene hash almacenado", analisis_id)
            return True

        # Recalcular hash del contenido actual
        content_str = json.dumps(report_content, sort_keys=True, ensure_ascii=False)
        current_hash = hashlib.sha256(content_str.encode("utf-8")).hexdigest()

        if current_hash == analisis.report_hash:
            return True  # Integridad verificada ✅

        # ⚠️ Discrepancia detectada — ASR-11
        empresa_id = str(analisis.empresa_id)

        self.audit_logger.log_security_event(
            event_type="INTEGRIDAD_COMPROMETIDA",
            user_email="sistema",
            ip="verificador-interno",
            action=(
                f"Hash mismatch en análisis {analisis_id}. "
                f"Almacenado={analisis.report_hash[:16]}... "
                f"Calculado={current_hash[:16]}..."
            ),
        )

        # Enviar alerta individual al responsable de la empresa (< 60s — ASR-11)
        responsable_email = self.responsable_email_fn(empresa_id)
        if responsable_email:
            subject, body = SESEmailAdapter.build_integrity_alert_email(
                analisis_id=analisis_id,
                empresa_nombre=empresa_id,
            )
            try:
                self.notification_service.send_email(
                    to=responsable_email, subject=subject, body=body
                )
            except Exception as exc:
                logger.error(
                    "No se pudo enviar alerta de integridad a %s: %s", responsable_email, exc
                )

        # Registrar en detector de anomalías — alerta escalada si hay patrón (ASR-11)
        try:
            from application.analisis_optimizacion.anomaly_detection import AnomalyDetector
            detector = AnomalyDetector(
                audit_logger=self.audit_logger,
                notification_service=self.notification_service,
                responsable_email_fn=self.responsable_email_fn,
            )
            detector.record_breach(empresa_id=empresa_id, analisis_id=analisis_id)
        except Exception as exc:
            logger.error("Error en detector de anomalías: %s", exc)

        return False  # Integridad comprometida ❌
