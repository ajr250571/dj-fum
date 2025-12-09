#!/bin/bash

# docker-entrypoint.sh
# Punto de entrada para contenedor Django con inicialización de tenants

echo "Esperando a que la base de datos esté lista..."
sleep 5

# Ejecutar migraciones
python manage.py migrate

# Crear superusuario si no existe
python manage.py shell <<EOF
import os
from django.contrib.auth import get_user_model

User = get_user_model()

if not User.objects.filter(username=os.environ.get('DJANGO_SUPERUSER_USERNAME', 'admin')).exists():
    print("Creando superusuario...")
    User.objects.create_superuser(
        os.environ.get('DJANGO_SUPERUSER_USERNAME', 'admin'),
        os.environ.get('DJANGO_SUPERUSER_EMAIL', 'admin@example.com'),
        os.environ.get('DJANGO_SUPERUSER_PASSWORD', 'admin123')
    )
    print("✓ Superusuario creado")
else:
    print("⚠ Superusuario ya existe")
EOF

# Inicializar tenants
python manage.py shell <<EOF
from customers.models import Client, Domain

print("Inicializando tenants...")

# Crear tenant público si no existe
tenant, created = Client.objects.get_or_create(
    schema_name='public',
    defaults={
        'name': 'Schemas Inc.',
        'paid_until': '2024-12-31',
        'on_trial': False
    }
)
if created:
    print(f"✓ Tenant público creado: {tenant.name}")
else:
    print("⚠ Tenant público ya existe")

# Crear dominio si no existe
domain, domain_created = Domain.objects.get_or_create(
    domain='localhost',
    defaults={
        'tenant': tenant,
        'is_primary': True
    }
)
if domain_created:
    print(f"✓ Dominio creado: {domain.domain}")
else:
    print("⚠ Dominio ya existe")

if not Client.objects.filter(schema_name='tenant1').exists():
    # create your first real tenant
    tenant = Client(schema_name='tenant1',
                    name='Fonzy Tenant',
                    paid_until='2014-12-05',
                    on_trial=True)
    tenant.save() 

    # Add one or more domains for the tenant
    domain = Domain()
    domain.domain = 'tenant1.localhost.com' 
    domain.tenant = tenant
    domain.is_primary = True
    domain.save()
else:
    print(f"⚠ Tenant1 ya existe")

print("✅ Inicialización completada")
EOF

