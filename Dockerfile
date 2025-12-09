# Dockerfile
FROM python:3.11-slim

# Evita que Python escriba archivos .pyc
ENV PYTHONDONTWRITEBYTECODE=1
# Evita que Python almacene en búfer stdout y stderr
ENV PYTHONUNBUFFERED=1

# Directorio de trabajo
WORKDIR /app

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Instalar dependencias de Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar proyecto
COPY . .
COPY .env /app/.env.local

# Puerto expuesto
EXPOSE 8000
EXPOSE 80 443



# COPY docker-entrypoint.sh /docker-entrypoint.sh
# RUN chmod +x ./docker-entrypoint.sh

RUN chmod +x ./init_tenants.sh

# Comando para ejecutar
CMD ["gunicorn", "core.wsgi:application", "--bind", "0.0.0.0:8000"]

# Definir entrypoint
# ENTRYPOINT ["/docker-entrypoint.sh"]
