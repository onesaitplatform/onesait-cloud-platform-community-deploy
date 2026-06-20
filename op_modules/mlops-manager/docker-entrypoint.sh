#!/bin/sh

mlflow server \
    --backend-store-uri "$STORE_URI" \
    --artifacts-destination "$ARTIFACT_STORE" \
    --host "$MLFLOW_SERVER_HOST" \
    --port "$MLFLOW_SERVER_PORT" \
    --allowed-hosts "*"
