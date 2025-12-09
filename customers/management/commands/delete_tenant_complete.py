# management/commands/delete_tenant_complete.py
from django.core.management.base import BaseCommand
from django.db import connection, transaction
from customers.models import Client
import sys


class Command(BaseCommand):
    help = 'Elimina un tenant completamente (incluyendo el schema)'

    def add_arguments(self, parser):
        parser.add_argument('schema_name', type=str, help='Nombre del schema')
        parser.add_argument(
            '--force',
            action='store_true',
            help='Eliminar sin confirmación',
        )
        parser.add_argument(
            '--keep-schema',
            action='store_true',
            help='Mantener el schema (solo eliminar registros)',
        )

    def handle(self, *args, **options):
        schema_name = options['schema_name']
        force = options['force']
        keep_schema = options['keep_schema']

        if schema_name == 'public':
            self.stderr.write(self.style.ERROR(
                '❌ No se puede eliminar el schema público'))
            sys.exit(1)

        try:
            tenant = Client.objects.get(schema_name=schema_name)
        except Client.DoesNotExist:
            self.stderr.write(self.style.ERROR(
                f'❌ Tenant "{schema_name}" no encontrado'))
            sys.exit(1)

        # Verificar si el schema existe en PostgreSQL
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.schemata 
                    WHERE schema_name = %s
                )
            """, [schema_name])
            schema_exists = cursor.fetchone()[0]

        self.stdout.write(self.style.WARNING(
            '\n⚠ ELIMINACIÓN COMPLETA DE TENANT'))
        self.stdout.write(f"   Tenant: {tenant.name}")
        self.stdout.write(f"   Schema: {schema_name}")
        self.stdout.write(
            f"   Schema en DB: {'✅ Existe' if schema_exists else '❌ No existe'}")

        if not keep_schema and schema_exists:
            # Contar tablas en el schema
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT COUNT(*) 
                    FROM information_schema.tables 
                    WHERE table_schema = %s
                """, [schema_name])
                table_count = cursor.fetchone()[0]

            self.stdout.write(f"   Tablas a eliminar: {table_count}")

        # Confirmación
        if not force:
            confirm = input(
                f"\n¿Eliminar {'schema y ' if not keep_schema else ''}tenant? (si/no): ")
            if confirm.lower() != 'si':
                self.stdout.write(self.style.WARNING('Operación cancelada'))
                return

        try:
            with transaction.atomic():
                # 1. Eliminar el tenant (registros)
                tenant_name = tenant.name
                tenant.delete()

                # 2. Eliminar el schema (si existe y no se especifica keep-schema)
                if not keep_schema and schema_exists:
                    self._drop_schema(schema_name)

                self.stdout.write(self.style.SUCCESS(
                    f'✅ Tenant "{tenant_name}" eliminado completamente'
                ))

        except Exception as e:
            self.stderr.write(self.style.ERROR(f'❌ Error: {e}'))
            sys.exit(1)

    def _drop_schema(self, schema_name):
        """Eliminar schema de PostgreSQL"""
        cursor = connection.cursor()

        try:
            # 1. Terminar conexiones activas al schema
            self.stdout.write(f"   Terminando conexiones activas...")
            cursor.execute("""
                SELECT pid, pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = current_database()
                AND state = 'active'
                AND query LIKE %s
            """, [f'%{schema_name}%'])

            # 2. Eliminar schema con CASCADE
            self.stdout.write(f"   Eliminando schema '{schema_name}'...")
            cursor.execute(f'DROP SCHEMA IF EXISTS "{schema_name}" CASCADE')

            self.stdout.write(self.style.SUCCESS(f"   ✅ Schema eliminado"))

        except Exception as e:
            raise Exception(f"No se pudo eliminar el schema: {e}")
        finally:
            cursor.close()
