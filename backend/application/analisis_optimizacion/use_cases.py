from core.shared.interfaces import IUnitOfWork, IAnalisisRepository, ITaskQueue, IAuditLogger
from core.analisis_optimizacion.entities import AnalisisConsumo
from application.analisis_optimizacion.dtos import AnalisisRequestDTO, AnalisisResponseDTO


class EjecutarAnalisisUseCase:
    # Patron de Inyeccion de Dependencias en el constructor
    def __init__(self, uow: IUnitOfWork, analisis_repo: IAnalisisRepository,
                 queue: ITaskQueue, audit_logger: IAuditLogger):
        self.uow = uow
        self.analisis_repo = analisis_repo
        self.queue = queue
        self.audit_logger = audit_logger

    def execute(self, request: AnalisisRequestDTO) -> AnalisisResponseDTO:
        with self.uow:
            # 1. Instanciar Agregado de Dominio
            analisis = AnalisisConsumo(
                empresa_id=request.empresa_id,
                tipo_analisis=request.tipo_analisis
            )
            analisis.solicitado_por = request.requested_by_email
            self.analisis_repo.save(analisis)

            # 2. Desviar ejecucion pesada a Cola Asincrona (ASR-11 Latencia)
            # user_email se incluye en el payload para que el Worker notifique al solicitante
            self.queue.enqueue_task(
                task_name="analisis_optimizacion.worker",
                payload={
                    "analisis_id": str(analisis.id),
                    "empresa_id": request.empresa_id,
                    "user_email": request.requested_by_email,
                }
            )

            # 3. Registrar accion en log inmutable (ASR-10)
            self.audit_logger.log_security_event(
                event_type="ANALISIS_REQUESTED",
                user_email=request.requested_by_email,
                ip="ObtenidaEnMiddleware",
                action=f"Encolado analisis ID {analisis.id}"
            )
            self.uow.commit()

        return AnalisisResponseDTO(analisis_id=str(analisis.id), estado=analisis.estado)
