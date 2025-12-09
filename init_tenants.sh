#!/bin/bash

# docker compose down  // -v borra base de datos
# docker compose up -d --build
# docker compose exec web bash

# chmod +x init_tenants.sh
# ./init_tenants.sh
# Script para inicializar tenants en Django con Docker

echo "Inicializando tenants..."

# Variables configurables
CONTAINER_NAME="web"  # Cambia esto por el nombre de tu contenedor Django
DOMAIN="${1:-localhost}"  # Usa el primer argumento o 'localhost' por defecto

python manage.py makemigrations
python manage.py migrate
python manage.py migrate_schemas --shared

# Ejecutar el comando dentro del contenedor
python manage.py shell <<EOF
# Crear superusuario si no existe
import os
from django.contrib.auth import get_user_model

User = get_user_model()

if not User.objects.filter(username=os.environ.get('DJANGO_SUPERUSER_USERNAME', 'admin')).exists():
    print("Creando superusuario...")
    User.objects.create_superuser(
        os.environ.get('DJANGO_SUPERUSER_EMAIL', 'admin@gmail.com'),
        os.environ.get('DJANGO_SUPERUSER_PASSWORD', 'admin123')
    )
    print("✓ Superusuario creado")
else:
    print("⚠ Superusuario ya existe")

from customers.models import Client, Domain

print("Creando tenant público...")
# Verificar si ya existe el tenant público
if not Client.objects.filter(schema_name='public').exists():
    # Crear el tenant público
    tenant = Client(
        schema_name='public',
        name='Schemas Inc.'
    )
    tenant.save()
    print(f"✓ Tenant público creado: {tenant.name}")
else:
    print("⚠ Tenant público ya existe")

# Verificar si ya existe el dominio
if not Domain.objects.filter(domain='${DOMAIN}').exists():
    # Agregar dominio para el tenant
    domain = Domain()
    domain.domain = '${DOMAIN}'  # Usar dominio pasado como argumento
    domain.tenant = tenant if 'tenant' in locals() else Client.objects.get(schema_name='public')
    domain.is_primary = True
    domain.save()
    print(f"✓ Dominio creado: {domain.domain}")
else:
    print(f"⚠ Dominio ${DOMAIN} ya existe")

if not Client.objects.filter(schema_name='tenant1').exists():
    # create your first real tenant
    tenant = Client(schema_name='tenant1',
                    name='Fonzy Tenant'
                    )
    tenant.save() 

    # Add one or more domains for the tenant
    domain = Domain()
    domain.domain = 'tenant1.localhost' 
    domain.tenant = tenant
    domain.is_primary = True
    domain.save()
else:
    print(f"⚠ Dominio ${DOMAIN} ya existe")

print("✅ Proceso completado")

EOF

# Crear tenant desde consola
python manage.py create_tenant \
    --schema_name=tenant1 \
    --name="Primer Tenant" \
    --domain_domain=tenant1.localhost \
    --domain_is_primary=True