"""
Django Settings — AQSF Platform
Configuración centralizada para el backend Django + Celery Worker.
"""

import os
from config.settings.env import settings as env

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-insecure-key-change-in-production")

DEBUG = os.environ.get("DJANGO_DEBUG", "False") == "True"

ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

# ---------------------------------------------------------------------------
# Apps instaladas
# ---------------------------------------------------------------------------
INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.staticfiles",
    "rest_framework",
    "infrastructure.database",
]

# ---------------------------------------------------------------------------
# Middleware — Orden crítico (ASR-10):
#   1. Auth0SecurityMiddleware → valida JWT, bloquea no autorizados, log inmutable
#   2. RateLimitMiddleware     → bloquea brute force y cross-tenant abuse
#   3. CommonMiddleware        → headers estándar
# ---------------------------------------------------------------------------
MIDDLEWARE = [
    "interfaces.middlewares.security_middleware.Auth0SecurityMiddleware",
    "interfaces.middlewares.rate_limit_middleware.RateLimitMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

# ---------------------------------------------------------------------------
# Base de datos — PostgreSQL RDS (ASR-10: credenciales vía env, no hardcodeadas)
# ---------------------------------------------------------------------------
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env.DB_NAME,
        "USER": env.DB_USER,
        "PASSWORD": env.DB_PASSWORD,  # Viene de .env — NUNCA hardcodeada (ASR-10)
        "HOST": env.DB_HOST,
        "PORT": env.DB_PORT,
        "CONN_MAX_AGE": 60,
    }
}

# ---------------------------------------------------------------------------
# Celery — Broker SQS (ASR-9)
# ---------------------------------------------------------------------------
CELERY_BROKER_URL = "sqs://"
CELERY_BROKER_TRANSPORT_OPTIONS = {
    "region": env.AWS_REGION,
    "predefined_queues": {
        env.AWS_SQS_QUEUE_NAME: {"url": env.AWS_SQS_URL}
    },
    "wait_time_seconds": 20,
    "visibility_timeout": 3600,
}
CELERY_TASK_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_IGNORE_RESULT = True
CELERY_TASK_ACKS_LATE = True
CELERY_WORKER_PREFETCH_MULTIPLIER = 1

# ---------------------------------------------------------------------------
# Django REST Framework
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    # La autenticación la maneja Auth0SecurityMiddleware (no DRF auth)
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    "DEFAULT_PERMISSION_CLASSES": [],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    # Evita que DRF intente cargar django.contrib.auth.models.AnonymousUser
    # cuando el usuario no está autenticado vía DRF (lo maneja Auth0SecurityMiddleware).
    # Sin esto, DRF lanza RuntimeError porque django.contrib.auth no está en INSTALLED_APPS.
    "UNAUTHENTICATED_USER": None,
}

# ---------------------------------------------------------------------------
# Internacionalización
# ---------------------------------------------------------------------------
LANGUAGE_CODE = "es-co"
TIME_ZONE = "America/Bogota"
USE_I18N = True
USE_TZ = True

# ---------------------------------------------------------------------------
# Logging — Formato estructurado para CloudWatch
# ---------------------------------------------------------------------------
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "format": '{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
        },
    },
    "root": {
        "handlers": ["console"],
        "level": "INFO",
    },
    "loggers": {
        "django": {"handlers": ["console"], "level": "WARNING", "propagate": False},
        "celery": {"handlers": ["console"], "level": "INFO",    "propagate": False},
    },
}

# ---------------------------------------------------------------------------
# Rate limiting (ASR-10) - Memoria
# ---------------------------------------------------------------------------

# Umbrales de rate limiting (ajustables por entorno)
RATE_LIMIT_FAILED_AUTH_MAX = int(os.environ.get("RATE_LIMIT_FAILED_AUTH_MAX", "10"))
RATE_LIMIT_WINDOW_SECONDS  = int(os.environ.get("RATE_LIMIT_WINDOW_SECONDS", "60"))
RATE_LIMIT_BLOCK_SECONDS   = int(os.environ.get("RATE_LIMIT_BLOCK_SECONDS", "300"))
RATE_LIMIT_CROSS_TENANT_MAX = int(os.environ.get("RATE_LIMIT_CROSS_TENANT_MAX", "3"))

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
STATIC_URL = "/static/"
STATIC_ROOT = "/app/staticfiles"
