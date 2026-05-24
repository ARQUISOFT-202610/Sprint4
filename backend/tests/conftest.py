import pytest
from unittest.mock import MagicMock
from core.shared.interfaces import ITaskQueue, INotificationService, IAuditLogger

@pytest.fixture
def mock_sqs(): return MagicMock(spec=ITaskQueue)

@pytest.fixture
def mock_ses(): return MagicMock(spec=INotificationService)

@pytest.fixture
def mock_cloudwatch(): return MagicMock(spec=IAuditLogger)
