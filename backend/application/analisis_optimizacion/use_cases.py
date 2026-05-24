from core.shared.interfaces import IUnitOfWork, IAnalisisRepository, ITaskQueue, IAuditLogger
from core.analisis_optimizacion.entities import AnalisisConsumo
from application.analisis_optimizacion.dtos import AnalisisRequestDTO, AnalisisResponseDTO

class EjecutarAnalisisUseCase:
    # Patrón de Inyección de Dependencias en el constructor
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
            self.analisis_repo.save(analisis)
            
            # 2. Desviar ejecución pesada a Cola Asíncrona (ASR-6)
            self.queue.enqueue_task(
                task_name="analisis_optimizacion.worker",
                payload={"analisis_id": str(analisis.id), "empresa_id": request.empresa_id}
            )
            
            # 3. Registrar acción en log inmutable (ASR-7)
            self.audit_logger.log_security_event(
                event_type="ANALISIS_REQUESTED",
                user_email=request.requested_by_email,
                ip="ObtenidaEnMiddleware", 
                action=f"Encolado análisis ID {analisis.id}"
            )
            self.uow.commit()

        return AnalisisResponseDTO(analisis_id=str(analisis.id), estado=analisis.estado)
