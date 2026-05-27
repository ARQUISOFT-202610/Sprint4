"""
Punto de entrada de Celery para el proyecto AQSF.
Referenciado por: celery -A config worker
"""
from infrastructure.messaging.celery_app import app

__all__ = ("app",)
