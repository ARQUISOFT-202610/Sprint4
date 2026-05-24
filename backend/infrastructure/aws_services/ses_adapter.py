"""
Adaptador SES — Servicio de Notificaciones por Correo
Implementa INotificationService usando AWS SES (ASR-9).

Características:
  - Envío de HTML + texto plano (fallback)
  - Manejo de errores con excepción propagada para que Celery reintente
  - Sin persistencia de credenciales en BD o logs (ASR-10)
"""

import boto3
from botocore.exceptions import ClientError

from core.shared.interfaces import INotificationService
from config.settings.env import settings


class SESEmailAdapter(INotificationService):
    def __init__(self):
        # Las credenciales provienen del IAM Role del EC2 (sin hardcodeo — ASR-10)
        self.client = boto3.client("ses", region_name=settings.AWS_REGION)
        self.from_email = settings.SES_FROM_EMAIL

    # ------------------------------------------------------------------
    # Interfaz pública
    # ------------------------------------------------------------------

    def send_email(self, to: str, subject: str, body: str) -> None:
        """
        Envía un correo HTML. Lanza excepción si SES falla
        (Celery capturará y reintentará según la política de backoff — ASR-9).
        """
        try:
            self.client.send_email(
                Source=self.from_email,
                Destination={"ToAddresses": [to]},
                Message={
                    "Subject": {"Data": subject, "Charset": "UTF-8"},
                    "Body": {
                        "Html": {"Data": body, "Charset": "UTF-8"},
                        "Text": {"Data": self._strip_html(body), "Charset": "UTF-8"},
                    },
                },
            )
        except ClientError as e:
            # Re-lanzar para que Celery maneje el reintento
            raise RuntimeError(
                f"SES falló al enviar correo a {to}: {e.response['Error']['Message']}"
            ) from e

    # ------------------------------------------------------------------
    # Helpers de plantillas de correo
    # ------------------------------------------------------------------

    @staticmethod
    def build_success_email(analisis_id: str, empresa_nombre: str, frontend_url: str) -> tuple[str, str]:
        """Retorna (subject, html_body) para correo de análisis completado."""
        subject = f"✅ Análisis de consumo completado — {empresa_nombre}"
        report_url = f"{frontend_url}/reportes/{analisis_id}"
        body = f"""
        <html><body style="font-family: Arial, sans-serif; color: #333;">
          <h2 style="color: #0a8a2f;">✅ Análisis completado</h2>
          <p>El análisis de consumo cloud para <strong>{empresa_nombre}</strong>
             ha finalizado exitosamente.</p>
          <p>
            <a href="{report_url}"
               style="background:#0a8a2f;color:#fff;padding:10px 20px;
                      text-decoration:none;border-radius:4px;">
              Ver reporte completo
            </a>
          </p>
          <hr/>
          <p style="font-size:12px;color:#888;">
            ID de análisis: {analisis_id}<br/>
            Este mensaje fue generado automáticamente por AQSF.
          </p>
        </body></html>
        """
        return subject, body

    @staticmethod
    def build_error_email(analisis_id: str, empresa_nombre: str, error_msg: str) -> tuple[str, str]:
        """Retorna (subject, html_body) para correo de análisis fallido."""
        subject = f"❌ Error en análisis de consumo — {empresa_nombre}"
        body = f"""
        <html><body style="font-family: Arial, sans-serif; color: #333;">
          <h2 style="color: #c0392b;">❌ Error en el análisis</h2>
          <p>El análisis de consumo cloud para <strong>{empresa_nombre}</strong>
             no pudo completarse.</p>
          <p><strong>Detalle:</strong> {error_msg}</p>
          <p>El equipo técnico fue notificado. Por favor intente nuevamente más tarde
             o contacte soporte si el problema persiste.</p>
          <hr/>
          <p style="font-size:12px;color:#888;">ID de análisis: {analisis_id}</p>
        </body></html>
        """
        return subject, body

    @staticmethod
    def build_integrity_alert_email(analisis_id: str, empresa_nombre: str) -> tuple[str, str]:
        """Retorna (subject, html_body) para alerta de integridad comprometida (ASR-11)."""
        subject = f"🚨 ALERTA: Integridad de reporte comprometida — {empresa_nombre}"
        body = f"""
        <html><body style="font-family: Arial, sans-serif; color: #333;">
          <h2 style="color: #c0392b;">🚨 Alerta de integridad</h2>
          <p>Se ha detectado una <strong>discrepancia en el hash SHA-256</strong>
             del reporte de análisis para <strong>{empresa_nombre}</strong>.</p>
          <p>Esto indica que el reporte puede haber sido modificado después de su generación.</p>
          <p><strong>Acción requerida:</strong> Revisar el reporte y los logs de auditoría
             en CloudWatch inmediatamente.</p>
          <hr/>
          <p style="font-size:12px;color:#888;">ID de análisis afectado: {analisis_id}</p>
        </body></html>
        """
        return subject, body

    # ------------------------------------------------------------------
    # Utilidades privadas
    # ------------------------------------------------------------------

    @staticmethod
    def _strip_html(html: str) -> str:
        """Elimina tags HTML para generar versión texto plano del correo."""
        import re
        return re.sub(r"<[^>]+>", "", html).strip()
