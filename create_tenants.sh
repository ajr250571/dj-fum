#!/bin/bash

# Script para crear múltiples tenants en Django
# Guardar como create_tenants.sh y dar permisos: chmod +x create_tenants.sh

# Configuración
PROJECT_PATH="/app"
PYTHON_PATH="/usr/bin/python"  # Ajusta según tu sistema
DJANGO_SETTINGS_MODULE="core.settings"

# Colores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para crear un tenant
create_tenant() {
    local SCHEMA_NAME="$1"
    local DOMAIN_NAME="$2"
    local TENANT_NAME="$3"
    local EMAIL="$4"
    
    echo "Creando tenant: $TENANT_NAME ($SCHEMA_NAME)"
    
    # Cambiar al directorio del proyecto
    cd "$PROJECT_PATH" || { log_error "No se pudo acceder a $PROJECT_PATH"; exit 1; }
    
    # Crear tenant usando django-admin shell
    "$PYTHON_PATH" manage.py shell <<EOF
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$DJANGO_SETTINGS_MODULE')

import django
django.setup()

from customers.models import Client, Domain
from django.contrib.auth import get_user_model
from django_tenants.utils import tenant_context

try:
    # Crear el tenant
    tenant = Client(
        schema_name='$SCHEMA_NAME',
        name='$TENANT_NAME',
        paid_until='2024-12-31',
        on_trial=True
    )
    tenant.save()
    
    # Crear dominio principal
    domain = Domain(
        domain='$DOMAIN_NAME',
        tenant=tenant,
        is_primary=True
    )
    domain.save()
    
    # Crear superusuario para este tenant
    with tenant_context(tenant):
        User = get_user_model()
        if not User.objects.filter(username='admin').exists():
            User.objects.create_superuser(
                username='admin',
                email='$EMAIL',
                password='admin123'  # Cambiar en producción
            )
            print(f"✓ Superusuario creado para $SCHEMA_NAME")
    
    print(f"✓ Tenant '$TENANT_NAME' creado exitosamente")
    
except Exception as e:
    print(f"✗ Error creando tenant $SCHEMA_NAME: {str(e)}")

EOF
}

# Función para crear múltiples tenants desde un archivo CSV
create_tenants_from_csv() {
    local CSV_FILE="$1"
    
    if [ ! -f "$CSV_FILE" ]; then
        log_error "Archivo $CSV_FILE no encontrado"
        exit 1
    fi
    
    echo "Creando tenants desde $CSV_FILE..."
    
    # Saltar la cabecera si existe
    tail -n +2 "$CSV_FILE" | while IFS=, read -r schema domain name email
    do
        # Limpiar espacios en blanco
        schema=$(echo "$schema" | xargs)
        domain=$(echo "$domain" | xargs)
        name=$(echo "$name" | xargs)
        email=$(echo "$email" | xargs)
        
        create_tenant "$schema" "$domain" "$name" "$email"
        echo "----------------------------------------"
    done
}

# Función para listar todos los tenants
list_tenants() {
    cd "$PROJECT_PATH" || exit 1
    
    echo "Listando todos los tenants:"
    
    "$PYTHON_PATH" manage.py shell <<EOF
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$DJANGO_SETTINGS_MODULE')

import django
django.setup()

from customers.models import Client, Domain

print(f"{'Schema Name':<20} {'Tenant Name':<30} {'Domain':<40} {'Created'}")
print("-" * 100)

tenants = Client.objects.all()
for tenant in tenants:
    domain = Domain.objects.filter(tenant=tenant, is_primary=True).first()
    domain_str = domain.domain if domain else 'No domain'
    print(f"{tenant.schema_name:<20} {tenant.name:<30} {domain_str:<40} {tenant.created_on}")

print(f"\nTotal tenants: {tenants.count()}")
EOF
}

# Función para eliminar un tenant
delete_tenant() {
    local SCHEMA_NAME="$1"
    
    cd "$PROJECT_PATH" || exit 1
    
    echo "Eliminando tenant: $SCHEMA_NAME"
    
    "$PYTHON_PATH" manage.py shell <<EOF
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$DJANGO_SETTINGS_MODULE')

import django
django.setup()

from customers.models import Client
from django_tenants.utils import get_tenant_model

try:
    tenant = Client.objects.get(schema_name='$SCHEMA_NAME')
    tenant.delete(force_drop=True)  # force_drop elimina el esquema
    print(f"✓ Tenant '$SCHEMA_NAME' eliminado exitosamente")
except Client.DoesNotExist:
    print(f"✗ Tenant '$SCHEMA_NAME' no encontrado")
except Exception as e:
    print(f"✗ Error eliminando tenant: {str(e)}")
EOF
}

# Menú principal
main_menu() {
    echo "========================================"
    echo "  Gestor de Tenants - Django Tenants    "
    echo "========================================"
    echo "1. Crear tenant individual"
    echo "2. Crear múltiples tenants desde CSV"
    echo "3. Listar todos los tenants"
    echo "4. Eliminar tenant"
    echo "5. Crear tenants de ejemplo"
    echo "6. Salir"
    echo "========================================"
    
    read -p "Selecciona una opción [1-6]: " choice
    
    case $choice in
        1)
            read -p "Schema name (ej: tenant1): " schema
            read -p "Domain (ej: tenant1.midominio.com): " domain
            read -p "Tenant name: " name
            read -p "Email admin: " email
            create_tenant "$schema" "$domain" "$name" "$email"
            ;;
        2)
            read -p "Ruta del archivo CSV: " csv_file
            create_tenants_from_csv "$csv_file"
            ;;
        3)
            list_tenants
            ;;
        4)
            read -p "Schema name a eliminar: " schema
            delete_tenant "$schema"
            ;;
        5)
            create_example_tenants
            ;;
        6)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            log_error "Opción no válida"
            ;;
    esac
}

# Función para crear tenants de ejemplo
create_example_tenants() {
    echo "Creando tenants de ejemplo..."
    
    # Array de tenants de ejemplo
    declare -A tenants
    tenants=(
        ["acme"]="Acme Corp|acme.midominio.com|acme@example.com"
        ["techsol"]="Tech Solutions|tech.midominio.com|tech@example.com"
        ["mktpro"]="Marketing Pro|marketing.midominio.com|mkt@example.com"
    )
    
    for schema in "${!tenants[@]}"; do
        IFS='|' read -r name domain email <<< "${tenants[$schema]}"
        create_tenant "$schema" "$domain" "$name" "$email"
        echo "----------------------------------------"
    done
    
    log_success "Tenants de ejemplo creados"
}

# Ejecutar directamente desde línea de comandos
if [[ $# -gt 0 ]]; then
    case $1 in
        "create")
            if [[ $# -eq 5 ]]; then
                create_tenant "$2" "$3" "$4" "$5"
            else
                echo "Uso: $0 create <schema> <domain> <name> <email>"
            fi
            ;;
        "list")
            list_tenants
            ;;
        "delete")
            if [[ $# -eq 2 ]]; then
                delete_tenant "$2"
            else
                echo "Uso: $0 delete <schema>"
            fi
            ;;
        "csv")
            if [[ $# -eq 2 ]]; then
                create_tenants_from_csv "$2"
            else
                echo "Uso: $0 csv <ruta_csv>"
            fi
            ;;
        "examples")
            create_example_tenants
            ;;
        *)
            echo "Comandos disponibles:"
            echo "  create <schema> <domain> <name> <email>"
            echo "  list"
            echo "  delete <schema>"
            echo "  csv <ruta_csv>"
            echo "  examples"
            ;;
    esac
else
    # Mostrar menú interactivo
    main_menu
fi