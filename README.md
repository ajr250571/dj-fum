docker compose up -d --build
docker compose down

## Tenants
docker-compose exec web python manage.py makemigrations
docker-compose exec web python manage.py migrate_schemas --shared
