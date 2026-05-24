from abc import ABC, abstractmethod

class IUnitOfWork(ABC):
    @abstractmethod
    def __enter__(self): pass
    @abstractmethod
    def __exit__(self, exc_type, exc_val, exc_tb): pass
    @abstractmethod
    def commit(self): pass

class IAnalisisRepository(ABC):
    @abstractmethod
    def save(self, analisis) -> None: pass

    @abstractmethod
    def get_by_id(self, analisis_id: str): pass

class ICloudProviderClient(ABC):
    # ASR-8: Solo operaciones de lectura permitidas
    @abstractmethod
    def fetch_usage_data(self, account_id: str) -> dict: pass

class INotificationService(ABC):
    @abstractmethod
    def send_email(self, to: str, subject: str, body: str): pass

class ITaskQueue(ABC):
    @abstractmethod
    def enqueue_task(self, task_name: str, payload: dict): pass

class IAuditLogger(ABC):
    # ASR-7: Contrato para logs inmutables
    @abstractmethod
    def log_security_event(self, event_type: str, user_email: str, ip: str, action: str): pass
