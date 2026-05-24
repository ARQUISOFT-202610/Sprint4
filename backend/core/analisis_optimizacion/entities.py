from core.shared.base import AggregateRoot
from datetime import datetime


class AnalisisConsumo(AggregateRoot):
    def __init__(self, empresa_id: str, tipo_analisis: str, id=None):
        super().__init__(id)
        self.empresa_id = empresa_id
        self.tipo_analisis = tipo_analisis
        self.estado = "PENDIENTE"
        self.fecha_ejecucion = None
        self.report_hash = None   # ASR-11: Integridad del reporte (hash SHA-256)
        self.solicitado_por = ""  # ASR-10: Trazabilidad del solicitante

    def iniciar_ejecucion(self):
        self.estado = "EN_PROGRESO"
        self.fecha_ejecucion = datetime.utcnow()

    def completar(self, report_hash: str):
        self.estado = "COMPLETADO"
        self.report_hash = report_hash
