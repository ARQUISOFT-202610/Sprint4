#!/bin/bash
# ============================================================
# start_django.sh — Script de arranque manual para Django
# Corre esto en la instancia si gunicorn no está levantado.
# Uso:
#   bash /home/ubuntu/Sprint4/terraform/scripts/start_django.sh \
#     "<RDS_HOST>" "<SQS_URL>" "<DB_PASSWORD>"
# O sin argumentos si el .env ya existe en /app/backend/.env
# ============================================================

set -euo pipefail

APP_DIR="/home/ubuntu/Sprint4/backend"
LOG_DIR="/tmp"
VENV="$APP_DIR/venv"

RDS_HOST="${1:-}"
SQS_URL="${2:-}"
DB_PASS="${3:-ArquiSoft2026Dev!}"

echo "=== Django Manual Bootstrap ==="
date

# ── 1. Asegura que el repo existe ──────────────────────────
if [ ! -d "$APP_DIR" ]; then
  echo "Clonando repositorio..."
  git clone https://github.com/ARQUISOFT-202610/Sprint4.git /home/ubuntu/Sprint4
fi

# ── 2. Crea o actualiza el .env si se pasaron argumentos ───
if [ -n "$RDS_HOST" ] && [ -n "$SQS_URL" ]; then
  echo "Escribiendo .env con los valores proporcionados..."
  cat > "$APP_DIR/.env" << EOF
DB_NAME=django_db
DB_USER=postgres
DB_PASSWORD=$DB_PASS
DB_HOST=$RDS_HOST
DB_PORT=5432
AWS_SQS_URL=$SQS_URL
AWS_SQS_QUEUE_NAME=arquisoft-celery-tasks
AWS_REGION=us-east-1
CLOUDWATCH_LOG_GROUP=/arquisoft/django/security
CLOUDWATCH_LOG_STREAM=security-audit
DJANGO_SETTINGS_MODULE=config.django_settings
ALLOWED_HOSTS=*
EOF
  echo ".env escrito OK"
fi

# ── 3. Verifica que el .env existe ─────────────────────────
if [ ! -f "$APP_DIR/.env" ]; then
  echo "ERROR: No existe $APP_DIR/.env — pasa RDS_HOST y SQS_URL como argumentos"
  exit 1
fi

# ── 4. Crea venv si no existe ──────────────────────────────
if [ ! -d "$VENV" ]; then
  echo "Creando virtual environment..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip setuptools wheel -q
  "$VENV/bin/pip" install -r "$APP_DIR/requirements.txt" -q
  echo "Dependencias instaladas OK"
fi

# ── 5. Carga .env y exporta variables ──────────────────────
set -a
source "$APP_DIR/.env"
set +a
export PYTHONPATH="$APP_DIR"
export DJANGO_SETTINGS_MODULE=config.django_settings
export ALLOWED_HOSTS="*"

# ── 6. Migraciones ─────────────────────────────────────────
echo "Corriendo migraciones..."
cd "$APP_DIR"
"$VENV/bin/python" manage.py migrate --run-syncdb --noinput && echo "Migraciones OK" || echo "WARN: migraciones fallaron, continuando..."

# ── 7. Mata gunicorn anterior si está corriendo ────────────
pkill -f "gunicorn config.wsgi" 2>/dev/null || true
sleep 2

# ── 8. Arranca gunicorn ────────────────────────────────────
echo "Arrancando gunicorn en puerto 8000..."
"$VENV/bin/gunicorn" config.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 4 \
  --worker-class gevent \
  --worker-connections 1000 \
  --timeout 120 \
  --daemon \
  --access-logfile "$LOG_DIR/gunicorn-access.log" \
  --error-logfile "$LOG_DIR/gunicorn-error.log"

sleep 3

# ── 9. Verifica ────────────────────────────────────────────
if curl -sf http://localhost:8000/health/ > /dev/null 2>&1; then
  echo "✅ Django OK — http://localhost:8000/health/"
else
  echo "❌ Health check falló — revisa $LOG_DIR/gunicorn-error.log"
  tail -20 "$LOG_DIR/gunicorn-error.log" 2>/dev/null || true
  exit 1
fi
