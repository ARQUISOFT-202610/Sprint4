from abc import ABC
from pydantic import BaseModel, ConfigDict
import uuid

class DomainException(Exception):
    """Excepción base para violaciones de reglas de negocio."""
    pass

class ValueObject(BaseModel):
    model_config = ConfigDict(frozen=True)

class Entity(ABC):
    def __init__(self, id: uuid.UUID = None):
        self.id = id or uuid.uuid4()

class AggregateRoot(Entity):
    """Marcador para identificar Raíces de Agregado en repositorios."""
    pass
