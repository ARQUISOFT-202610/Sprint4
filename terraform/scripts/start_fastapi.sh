#!/bin/bash
# ============================================================
# start_fastapi.sh — Script de arranque manual para FastAPI
# Corre esto en cada instancia FastAPI si uvicorn no está levantado.
# Uso:
#   bash /home/ubuntu/Sprint4/terraform/scripts/start_fastapi.sh "<DYNAMODB_PRIVATE_IP>"
# ============================================================

set -euo pipefail

APP_DIR="/home/ubuntu/Sprint4/backend"
LOG_DIR="/tmp"
VENV="$APP_DIR/venv"

DYNAMODB_IP="${1:-10.0.1.4}"

echo "=== FastAPI Manual Bootstrap ==="
date

# ── 1. Asegura que el repo existe ──────────────────────────
if [ ! -d "$APP_DIR" ]; then
  echo "Clonando repositorio..."
  git clone https://github.com/ARQUISOFT-202610/Sprint4.git /home/ubuntu/Sprint4
fi

# ── 2. Escribe el .env ─────────────────────────────────────
echo "Escribiendo .env..."
cat > "$APP_DIR/.env" << EOF
DYNAMODB_ENDPOINT=http://$DYNAMODB_IP:8000
AWS_REGION=us-east-1
CLOUDWATCH_LOG_GROUP=/arquisoft/fastapi
CLOUDWATCH_LOG_STREAM=main
AUTH0_DOMAIN=dev-qcbziogvv5h4151u.us.auth0.com
AUTH0_AUDIENCE=https://measurements/api
EOF
echo ".env escrito OK"

# ── 3. Crea venv si no existe ──────────────────────────────
if [ ! -d "$VENV" ]; then
  echo "Creando virtual environment..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip setuptools wheel -q
  "$VENV/bin/pip" install -r "$APP_DIR/requirements.txt" -q
  echo "Dependencias instaladas OK"
fi

# ── 4. Carga .env ──────────────────────────────────────────
set -a
source "$APP_DIR/.env"
set +a
export PYTHONPATH="$APP_DIR"

# ── 5. Mata uvicorn anterior si está corriendo ─────────────
pkill -f "uvicorn main:app" 2>/dev/null || true
sleep 2

# ── 6. Arranca uvicorn ─────────────────────────────────────
echo "Arrancando uvicorn en puerto 8001..."
cd "$APP_DIR"
"$VENV/bin/uvicorn" main:app \
  --host 0.0.0.0 \
  --port 8001 \
  --workers 4 \
  --log-level info \
  --access-log \
  2>"$LOG_DIR/uvicorn-error.log" &
disown

sleep 3

# ── 7. Verifica ────────────────────────────────────────────
if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
  echo "✅ FastAPI OK — http://localhost:8001/health"
else
  echo "❌ Health check falló — revisa $LOG_DIR/uvicorn-error.log"
  tail -20 "$LOG_DIR/uvicorn-error.log" 2>/dev/null || true
  exit 1
fi
