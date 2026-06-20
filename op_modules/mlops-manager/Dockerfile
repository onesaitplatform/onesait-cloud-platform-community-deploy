FROM python:3.12-slim AS builder

LABEL module.maintainer="indramindplatform@indra.es" \
    module.name="mlflow" \
    module.mlflow.version="3.10.1"

ENV MLFLOW_VERSION=3.10.1

RUN pip install --no-cache-dir --upgrade pip

RUN pip install --no-cache-dir \
    mlflow[auth]==${MLFLOW_VERSION} \
    boto3 \
    flask \
    pyjwt \
    requests \
    werkzeug \
    protobuf==6.33.5 \
    "numpy>=1.26.4,<2.0" \
    sqlalchemy==2.0.25 \
    pymysql


FROM python:3.12-slim

LABEL module.maintainer="indramindplatform@indra.es" \
    module.name="mlflow" \
    module.mlflow.version="3.10.1"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MLFLOW_SERVER_PORT=5000 \
    MLFLOW_SERVER_HOST=0.0.0.0 \
    MLFLOW_AUTH_CONFIG_PATH=/opt/mlflow-config/basic_auth.ini

COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin

# Copiamos auth config y script
RUN mkdir -p /opt/mlflow-config
COPY basic_auth.ini /opt/mlflow-config/basic_auth.ini
COPY patches/jwt_auth.py /usr/local/lib/python3.12/site-packages/mlflow/server/auth/jwt_auth.py
COPY patches/8606fa83a998_initial_migration.py /usr/local/lib/python3.12/site-packages/mlflow/server/auth/db/migrations/versions/8606fa83a998_initial_migration.py
# COPY patches/env.py /usr/local/lib/python3.12/site-packages/mlflow/server/auth/db/migrations/env.py
# Fix: CP sends max_results=0 (empty body {}), MLflow 3.x rejects it - treat 0 as default 1000
COPY patches/fix_search_experiments_max_results.py /tmp/fix_search_experiments_max_results.py
RUN python3 /tmp/fix_search_experiments_max_results.py

# Entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
RUN mkdir -p /mlruns && chmod -R 777 /mlruns
RUN chmod 777 /opt/mlflow-config \
    && chmod -R 777 /usr/local/lib/python3.12/site-packages/mlflow/server/auth/db/migrations


WORKDIR /

EXPOSE 5000

ENTRYPOINT ["./docker-entrypoint.sh"]