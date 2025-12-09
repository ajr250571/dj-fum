# management/commands/cleanup_orphaned_schemas.py
from django.core.management.base import BaseCommand
from django.db import connection
from customers.models import Client


class Command(BaseCommand):
    help = 'Elimina schemas que existen en PostgreSQL pero no tienen tenant asociado'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Mostrar qué se eliminaría sin ejecutar',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']

        # Obtener todos los schemas de PostgreSQL
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT schema_name 
                FROM information_schema.schemata 
                WHERE schema_name NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
                AND schema_name NOT LIKE 'pg_%'
            """)
            all_schemas = {row[0] for row in cursor.fetchall()}

        # Obtener schemas de tenants registrados
        tenant_schemas = set(
            Client.objects.values_list('schema_name', flat=True))

        # Schemas huérfanos = existen en DB pero no en Django
        orphaned_schemas = all_schemas - tenant_schemas

        # Siempre mantener 'public'
        if 'public' in orphaned_schemas:
            orphaned_schemas.remove('public')

        if not orphaned_schemas:
            self.stdout.write(self.style.SUCCESS('✅ No hay schemas huérfanos'))
            return

        self.stdout.write(self.style.WARNING(
            f'📋 Schemas huérfanos encontrados: {len(orphaned_schemas)}'))

        for schema in sorted(orphaned_schemas):
            # Contar tablas en el schema
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT COUNT(*) 
                    FROM information_schema.tables 
                    WHERE table_schema = %s
                """, [schema])
                table_count = cursor.fetchone()[0]

            self.stdout.write(f"   • {schema} ({table_count} tablas)")

        if dry_run:
            self.stdout.write(self.style.WARNING(
                '\n⚠ Modo dry-run: no se eliminó nada'))
            return

        # Confirmación
        confirm = input(
            f"\n¿Eliminar {len(orphaned_schemas)} schemas huérfanos? (si/no): ")
        if confirm.lower() != 'si':
            self.stdout.write(self.style.WARNING('Operación cancelada'))
            return

        # Eliminar schemas
        deleted_count = 0
        with connection.cursor() as cursor:
            for schema in orphaned_schemas:
                try:
                    cursor.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')
                    deleted_count += 1
                    self.stdout.write(f"✅ Eliminado: {schema}")
                except Exception as e:
                    self.stdout.write(self.style.ERROR(
                        f"❌ Error eliminando {schema}: {e}"))

        self.stdout.write(self.style.SUCCESS(
            f'\n🗑️ {deleted_count}/{len(orphaned_schemas)} schemas eliminados'))
