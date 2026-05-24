import pytest
from unittest.mock import MagicMock
from application.analisis_optimizacion.use_cases import EjecutarAnalisisUseCase
from application.analisis_optimizacion.dtos import AnalisisRequestDTO
from core.shared.interfaces import IUnitOfWork, IAnalisisRepository

class MockUnitOfWork(IUnitOfWork):
    def __enter__(self): return self
    def __exit__(self, exc_type, exc_val, exc_tb): pass
    def commit(self): pass

class MockRepository(IAnalisisRepository):
    def __init__(self):
        self.saved_entities = []
    def save(self, analisis):
        self.saved_entities.append(analisis)

def test_ejecutar_analisis_use_case_flujo_exitoso(mock_sqs, mock_cloudwatch):
    # Arrange (Preparar dependencias Mock)
    uow = MockUnitOfWork()
    repo = MockRepository()
    use_case = EjecutarAnalisisUseCase(
        uow=uow,
        analisis_repo=repo,
        queue=mock_sqs,
        audit_logger=mock_cloudwatch
    )
    
    dto = AnalisisRequestDTO(
        empresa_id="empresa-123",
        tipo_analisis="optimizacion-costos",
        requested_by_email="admin@empresa.com"
    )
    
    # Act (Ejecutar caso de uso principal)
    response = use_case.execute(dto)
    
    # Assert (Verificar ASRs y lógica)
    assert response.estado == "PENDIENTE"
    assert response.analisis_id is not None
    
    # 1. Verificar guardado
    assert len(repo.saved_entities) == 1
    assert repo.saved_entities[0].empresa_id == "empresa-123"
    
    # 2. Verificar encolamiento asíncrono (ASR-6)
    mock_sqs.enqueue_task.assert_called_once()
    args, kwargs = mock_sqs.enqueue_task.call_args
    assert kwargs["task_name"] == "analisis_optimizacion.worker"
    assert kwargs["payload"]["empresa_id"] == "empresa-123"
    
    # 3. Verificar log inmutable (ASR-7)
    mock_cloudwatch.log_security_event.assert_called_once()
    args, kwargs = mock_cloudwatch.log_security_event.call_args
    assert kwargs["event_type"] == "ANALISIS_REQUESTED"
    assert kwargs["user_email"] == "admin@empresa.com"
