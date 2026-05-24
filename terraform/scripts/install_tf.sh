#!/bin/bash

set -e

# ==============================
# Variables
# ==============================
TFENV_PATH="$HOME/.tfenv"
CACHE_DIR="/tmp/terraform-cache"
BASH_RC="$HOME/.bashrc"

echo "--- Iniciando configuración de Terraform en AWS CloudShell ---"

# ==============================
# Configurar cache de plugins
# ==============================
mkdir -p "$CACHE_DIR"
export TF_PLUGIN_CACHE_DIR="$CACHE_DIR"

if ! grep -q "TF_PLUGIN_CACHE_DIR" "$BASH_RC"; then
    echo "Configurando caché persistente..."
    {
        echo ""
        echo "# Terraform Plugin Cache"
        echo "mkdir -p $CACHE_DIR"
        echo "export TF_PLUGIN_CACHE_DIR=\"$CACHE_DIR\""
    } >> "$BASH_RC"
fi

# ==============================
# Instalar tfenv
# ==============================
if [ ! -d "$TFENV_PATH" ]; then
    echo "Instalando tfenv..."
    git clone --depth=1 https://github.com/tfutils/tfenv.git "$TFENV_PATH"
else
    echo "tfenv ya está instalado."
fi

# ==============================
# Configurar PATH
# ==============================
export PATH="$TFENV_PATH/bin:$PATH"

if ! grep -q 'tfenv/bin' "$BASH_RC"; then
    {
        echo ""
        echo "# tfenv"
        echo "export PATH=\"$TFENV_PATH/bin:\$PATH\""
    } >> "$BASH_RC"
fi

# ==============================
# Verificar/Instalar Terraform
# ==============================
if ! terraform version >/dev/null 2>&1; then
    echo "Instalando última versión estable de Terraform..."

    tfenv install latest
    tfenv use latest

    echo "Terraform instalado correctamente."
else
    echo "Terraform ya disponible:"
    terraform version | head -n 1
fi

# ==============================
# Configurar alias
# ==============================
echo "Configurando alias útiles..."

declare -A aliases=(
    ["tfi"]="terraform init"
    ["tfp"]="terraform plan"
    ["tfa"]="terraform apply"
    ["tfd"]="terraform destroy"
    ["tfv"]="terraform validate"
)

for alias_name in "${!aliases[@]}"; do
    if ! grep -q "alias $alias_name=" "$BASH_RC"; then
        echo "alias $alias_name='${aliases[$alias_name]}'" >> "$BASH_RC"
    fi
done

# ==============================
# Finalización
# ==============================
echo ""
echo "--- Configuración completada ---"
echo "Ejecuta:"
echo "source ~/.bashrc"
echo ""

terraform version