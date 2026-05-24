from django.db import transaction
from django.utils import timezone
from core.shared.interfaces import IAnalisisRepository, IUnitOfWork
from core.analisis_optimizacion.entities import AnalisisConsumo
from infrastructure.database.models import AnalisisConsumoModel


class DjangoUnitOfWork(IUnitOfWork):
    def __enter__(self):
        self.transaction = transaction.atomic()
        self.transaction.__enter__()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.transaction.__exit__(exc_type, exc_val, exc_tb)

    def commit(self):
        pass  # Django atomic() confirma al salir del bloque sin excepción


class DjangoAnalisisRepository(IAnalisisRepository):
    def save(self, analisis: AnalisisConsumo) -> None:
        defaults = {
            "empresa_id": analisis.empresa_id,
            "tipo_analisis": analisis.tipo_analisis,
            "estado": analisis.estado,
            "report_hash": analisis.report_hash,
        }
        # Persistir email del solicitante si está disponible
        if hasattr(analisis, "solicitado_por"):
            defaults["solicitado_por"] = analisis.solicitado_por
        # Registrar timestamp de completado
        if analisis.estado == "COMPLETADO":
            defaults["completado_en"] = timezone.now()

        AnalisisConsumoModel.objects.update_or_create(id=analisis.id, defaults=defaults)

    def get_by_id(self, analisis_id: str) -> AnalisisConsumo:
        """Recupera un AnalisisConsumo desde la BD y lo mapea a la entidad de dominio."""
        try:
            model = AnalisisConsumoModel.objects.get(id=analisis_id)
        except AnalisisConsumoModel.DoesNotExist:
            raise ValueError(f"Análisis {analisis_id} no encontrado en la base de datos")

        analisis = AnalisisConsumo(
            empresa_id=str(model.empresa_id),
            tipo_analisis=model.tipo_analisis,
            id=model.id,
        )
        analisis.estado = model.estado
        analisis.report_hash = model.report_hash
        if hasattr(analisis, "solicitado_por"):
            analisis.solicitado_por = model.solicitado_por
        return analisis
