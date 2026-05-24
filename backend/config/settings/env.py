# Configuración de Entorno
from pydantic_settings import BaseSettings

class AppSettings(BaseSettings):
    # AWS General
    AWS_REGION: str = "us-east-1"

    # SQS — Broker de Celery (ASR-9)
    AWS_SQS_URL: str = ""
    AWS_SQS_QUEUE_NAME: str = "arquisoft-celery-tasks"

    # SES — Notificaciones por correo (ASR-9)
    SES_FROM_EMAIL: str = "no-reply@aqsf.example.com"

    # Auth0 — Autenticación / Autorización (ASR-10)
    AUTH0_DOMAIN: str = "dev-qcbziogvv5h4151u.us.auth0.com"
    AUTH0_AUDIENCE: str = "https://measurements/api"

    # PostgreSQL RDS
    DB_NAME: str = "django_db"
    DB_USER: str = "postgres"
    DB_PASSWORD: str = ""
    DB_HOST: str = "localhost"
    DB_PORT: str = "5432"

    # CloudWatch — Auditoría inmutable (ASR-10 / ASR-11)
    CLOUDWATCH_LOG_GROUP: str = "/aqsf/security-audit"
    CLOUDWATCH_LOG_STREAM: str = "main"

    # Celery — reintentos con backoff exponencial (ASR-9)
    CELERY_TASK_MAX_RETRIES: int = 3
    CELERY_TASK_RETRY_BACKOFF: int = 2  # segundos base para backoff

    # Frontend — URL base para enlaces en correos
    FRONTEND_URL: str = "http://localhost:3000"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = AppSettings()
