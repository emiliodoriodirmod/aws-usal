# Dockerfile para AWS ECS Demo
# Usa Python 3.9 slim para optimizar tamaño
FROM python:3.9-slim

# Metadata
LABEL maintainer="AWS Demo Class"
LABEL version="1.0"
LABEL description="Container demo para AWS ECS"

# Variables de entorno
ENV PYTHONUNBUFFERED=1
ENV APP_HOME=/app
ENV SERVICE_NAME="Amazon ECS"

# Crear directorio de trabajo
WORKDIR ${APP_HOME}

# Instalar dependencias del sistema
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements
COPY requirements.txt .

# Instalar dependencias Python
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código de la aplicación
COPY app.py .

# Crear usuario no-root para seguridad
RUN useradd -m -U -r appuser && \
    chown -R appuser:appuser ${APP_HOME}

# Cambiar al usuario no-root
USER appuser

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

# Puerto de la aplicación (informativo)
EXPOSE 8080

# Comando de inicio
CMD ["python", "app.py"]