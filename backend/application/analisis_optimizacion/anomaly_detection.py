"""
Detección de Anomalías de Integridad (ASR-11)

Implementa el criterio: "Patrones sospechosos (múltiples alteraciones en corto
tiempo) generan alerta automática."

Estrategia:
  - Cada vez que se detecta una discrepancia de hash para una empresa,
    se incrementa un contador en Redis con TTL de WINDOW_SECONDS.
  - Si el contador alcanza THRESHOLD en la misma ventana temporal,
    se genera un log CloudWatch con evento ANOMALIA_INTEGRIDAD y se
    envía una alerta escalada por SES al responsable.

Thresholds (configurables via env):
  ANOMALY_THRESHOLD       = 3  alteraciones en...
  ANOMALY_WINDOW_SECONDS  = 300 segundos (5 minutos)
"""

import logging
from typing import Callable

from config.settings.env import settings
from core.shared.interfaces import IAuditLogger, INotificationService
from infrastructure.aws_services.ses_adapter import SESEmailAdapter

logger = logging.getLogger(__name__)

THRESHOLD      = int(getattr(settings, "ANOMALY_THRESHOLD", 3))
WINDOW_SECONDS = int(getattr(settings, "ANOMALY_WINDOW_SECONDS", 300))


class AnomalyDetector:
    """
    Detecta patrones anómalos de alteración de integridad (ASR-11).
    Usa el mismo RateLimitStore del Exp-2 (Redis + fallback memoria).
    """

    def __init__(
        self,
        audit_logger: IAuditLogger,
        notification_service: INotificationService,
        responsable_email_fn: Callable[[str], str],
    ):
        self.audit_logger         = audit_logger
        self.notification_service = notification_service
        self.responsable_email_fn = responsable_email_fn
        # Reusar la misma abstracción Redis/memoria del rate limiter
        from interfaces.middlewares.rate_limit_middleware import RateLimitStore
        self.store = RateLimitStore()

    # ------------------------------------------------------------------
    # Interfaz pública
    # ------------------------------------------------------------------

    def record_breach(self, empresa_id: str, analisis_id: str) -> bool:
        """
        Registra una alteración de integridad para la empresa y verifica si
        hay un patrón anómalo.

        Retorna True si se alcanzó el umbral y se disparó una alerta escalada.
        """
        key   = f"integrity:breach:{empresa_id}"
        count = self.store.incr_with_ttl(key, WINDOW_SECONDS)

        logger.info(
            "Alteración de integridad registrada. EmpresaId=%s AnalisisId=%s Count=%d/%d",
            empresa_id, analisis_id, count, THRESHOLD,
        )

        # Log inmutable de cada alteración individual (ASR-11)
        self.audit_logger.log_security_event(
            event_type="ALTERACION_INTEGRIDAD",
            user_email="sistema",
            ip="detector-integridad",
            action=(
                f"Hash mismatch #{count} para empresa {empresa_id} "
                f"en ventana de {WINDOW_SECONDS}s. AnalisisId={analisis_id}"
            ),
        )

        if count >= THRESHOLD:
            return self._dispatch_anomaly_alert(empresa_id, analisis_id, count)

        return False

    # ------------------------------------------------------------------
    # Alerta escalada por patrón anómalo
    # ------------------------------------------------------------------

    def _dispatch_anomaly_alert(self, empresa_id: str, analisis_id: str, count: int) -> bool:
        """
        Dispara alerta escalada: log CloudWatch con ANOMALIA_INTEGRIDAD
        + correo urgente al responsable.
        """
        # Log CloudWatch de nivel CRÍTICO (ASR-11)
        self.audit_logger.log_security_event(
            event_type="ANOMALIA_INTEGRIDAD",
            user_email="sistema",
            ip="detector-automatico",
            action=(
                f"PATRÓN ANÓMALO: {count} alteraciones de integridad detectadas "
                f"para empresa {empresa_id} en menos de {WINDOW_SECONDS // 60} minutos. "
                f"Última alteración: AnalisisId={analisis_id}"
            ),
        )
        logger.critical(
            "ANOMALÍA DE INTEGRIDAD. EmpresaId=%s Count=%d en %ds",
            empresa_id, count, WINDOW_SECONDS,
        )

        # Correo escalado al responsable (< 60s — ASR-11)
        responsable_email = self.responsable_email_fn(empresa_id)
        if not responsable_email:
            logger.error("No hay email de responsable para empresa %s", empresa_id)
            return True  # La anomalía fue detectada aunque no se pueda notificar

        subject = f"🚨 ALERTA CRÍTICA: Patrón de alteración de integridad — empresa {empresa_id[:8]}..."
        body = f"""
        <html><body style="font-family:Arial,sans-serif;color:#333;">
          <h2 style="color:#c0392b;">🚨 Patrón Anómalo Detectado</h2>
          <p>El sistema ha detectado <strong>{count} alteraciones de integridad</strong>
             en menos de <strong>{WINDOW_SECONDS // 60} minutos</strong>
             para su empresa.</p>
          <table style="border-collapse:collapse;width:100%;">
            <tr style="background:#f8d7da;">
              <td style="padding:8px;border:1px solid #ddd;"><strong>Empresa ID</strong></td>
              <td style="padding:8px;border:1px solid #ddd;">{empresa_id}</td>
            </tr>
            <tr>
              <td style="padding:8px;border:1px solid #ddd;"><strong>Alteraciones detectadas</strong></td>
              <td style="padding:8px;border:1px solid #ddd;">{count} en {WINDOW_SECONDS // 60} min</td>
            </tr>
            <tr style="background:#f8d7da;">
              <td style="padding:8px;border:1px solid #ddd;"><strong>Último análisis afectado</strong></td>
              <td style="padding:8px;border:1px solid #ddd;">{analisis_id}</td>
            </tr>
          </table>
          <p style="margin-top:16px;"><strong>Acción requerida inmediatamente:</strong></p>
          <ol>
            <li>Revisar los logs de auditoría en AWS CloudWatch (<code>/aqsf/security-audit</code>)</li>
            <li>Identificar el origen de las modificaciones</li>
            <li>Contactar al equipo de seguridad</li>
          </ol>
          <hr/>
          <p style="font-size:12px;color:#888;">
            Este mensaje fue generado automáticamente por el sistema de detección de anomalías AQSF.
          </p>
        </body></html>
        """
        try:
            self.notification_service.send_email(
                to=responsable_email, subject=subject, body=body
            )
            logger.info("Alerta de anomalía enviada a %s", responsable_email)
        except Exception as exc:
            logger.error("Error enviando alerta de anomalía: %s", exc)

        return True
