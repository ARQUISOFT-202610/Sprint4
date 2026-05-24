"""
Adaptador CloudWatch Metrics — Lectura de consumo cloud del cliente (ASR-11).

SOLO OPERACIONES DE LECTURA. Cualquier intento de escritura debe ser rechazado
y registrado (ASR-11: el sistema opera en modo lectura sobre APIs de AWS).

En producción: consulta CloudWatch GetMetricStatistics para EC2, RDS, S3, etc.
"""

import logging
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

from core.shared.interfaces import ICloudProviderClient
from config.settings.env import settings

logger = logging.getLogger(__name__)

# Conjunto explícito de operaciones PERMITIDAS (lectura)
_ALLOWED_OPERATIONS = frozenset([
    "get_metric_statistics",
    "list_metrics",
    "describe_alarms",
    "get_metric_data",
])


class CloudWatchMetricsAdapter(ICloudProviderClient):
    """
    Consulta métricas de consumo cloud via CloudWatch (solo lectura — ASR-11).
    Las credenciales provienen del IAM Role del EC2 (sin hardcodeo — ASR-10).
    """

    def __init__(self):
        self.client = boto3.client("cloudwatch", region_name=settings.AWS_REGION)
        self.ce_client = boto3.client("ce", region_name="us-east-1")  # Cost Explorer

    def fetch_usage_data(self, account_id: str) -> dict:
        """
        Recupera datos de consumo cloud para la empresa indicada.
        Retorna dict con costos por servicio y total mensual.
        """
        logger.info("CloudWatch: leyendo métricas para empresa %s", account_id)
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=30)

        try:
            # Consulta de costos (solo lectura — ASR-11)
            cost_data = self._fetch_cost_by_service(
                start=start_date.strftime("%Y-%m-%d"),
                end=end_date.strftime("%Y-%m-%d"),
            )
            return {
                "empresa_id": account_id,
                "empresa_nombre": f"Empresa {account_id[:8]}",
                "periodo": {
                    "desde": start_date.strftime("%Y-%m-%d"),
                    "hasta": end_date.strftime("%Y-%m-%d"),
                },
                "servicios": cost_data,
                "total_usd": sum(cost_data.values()),
                "generado_en": end_date.isoformat(),
            }
        except ClientError as e:
            logger.error("Error leyendo métricas CloudWatch: %s", e)
            # Fallback: datos simulados para demostración
            return self._mock_usage_data(account_id, end_date)

    # ------------------------------------------------------------------
    # Métodos privados — SOLO LECTURA
    # ------------------------------------------------------------------

    def _fetch_cost_by_service(self, start: str, end: str) -> dict:
        """
        Usa Cost Explorer para obtener costos por servicio (GET — solo lectura).
        """
        response = self.ce_client.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["BlendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        costs = {}
        for result in response.get("ResultsByTime", []):
            for group in result.get("Groups", []):
                service = group["Keys"][0]
                amount = float(group["Metrics"]["BlendedCost"]["Amount"])
                costs[service] = round(amount, 4)
        return costs

    @staticmethod
    def _mock_usage_data(account_id: str, ts: datetime) -> dict:
        """Datos simulados para entornos sin Cost Explorer habilitado."""
        return {
            "empresa_id": account_id,
            "empresa_nombre": f"Empresa Demo {account_id[:8]}",
            "periodo": {
                "desde": (ts - timedelta(days=30)).strftime("%Y-%m-%d"),
                "hasta": ts.strftime("%Y-%m-%d"),
            },
            "servicios": {
                "Amazon EC2": 150.00,
                "Amazon RDS": 200.00,
                "Amazon S3": 45.00,
                "AWS Lambda": 12.50,
                "Amazon CloudWatch": 8.00,
            },
            "total_usd": 415.50,
            "generado_en": ts.isoformat(),
            "es_mock": True,
        }

    # ------------------------------------------------------------------
    # Protección explícita contra escritura (ASR-11)
    # ------------------------------------------------------------------

    def _reject_write_operation(self, operation: str, context: str = "") -> None:
        """
        Lanza excepción si se intenta ejecutar una operación de escritura.
        Registra el intento para auditoría.
        """
        if operation not in _ALLOWED_OPERATIONS:
            from infrastructure.aws_services.adapters import CloudWatchAuditLogger
            try:
                audit = CloudWatchAuditLogger()
                audit.log_security_event(
                    event_type="ESCRITURA_RECHAZADA",
                    user_email="sistema",
                    ip="cloud-adapter",
                    action=f"Intento de operación no permitida: {operation}. Contexto: {context}",
                )
            except Exception:
                pass
            raise PermissionError(
                f"Operación '{operation}' no está permitida. "
                "El sistema opera en modo solo lectura sobre APIs de AWS (ASR-11)."
            )
