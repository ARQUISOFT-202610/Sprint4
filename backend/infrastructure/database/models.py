from django.db import models
import uuid

class EmpresaModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    nombre = models.CharField(max_length=255)
    nit = models.CharField(max_length=50)
    # Email del responsable — receptor de alertas ASR-11
    responsable_email = models.EmailField(max_length=254, null=True, blank=True)

    class Meta:
        db_table = "empresa"


class AnalisisConsumoModel(models.Model):
    ESTADO_PENDIENTE    = "PENDIENTE"
    ESTADO_EN_PROGRESO  = "EN_PROGRESO"
    ESTADO_COMPLETADO   = "COMPLETADO"
    ESTADO_FALLIDO      = "FALLIDO"

    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    empresa_id     = models.UUIDField(db_index=True)
    tipo_analisis  = models.CharField(max_length=100)
    estado         = models.CharField(max_length=50, default=ESTADO_PENDIENTE)
    # ASR-11: Hash SHA-256 para verificación de integridad del reporte
    report_hash    = models.CharField(max_length=64, null=True, blank=True)
    # Trazabilidad: quién solicitó el análisis (ASR-10)
    solicitado_por = models.EmailField(max_length=254, null=True, blank=True)
    # Timestamps
    creado_en      = models.DateTimeField(auto_now_add=True)
    completado_en  = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "analisis_consumo"
