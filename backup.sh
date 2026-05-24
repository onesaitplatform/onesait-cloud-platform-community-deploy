#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$BASE_DIR/db_seed"

echo "Generando copias de seguridad (Dumps) de las bases de datos..."

# 1. Backup MariaDB
echo "Exportando configdb (MariaDB)..."
docker exec -i configdb mysqldump -u root -pchangeIt! --all-databases > "$BASE_DIR/db_seed/configdb.sql"

# 2. Backup MongoDB
echo "Exportando realtimedb (MongoDB)..."
docker exec -i realtimedb mongodump --out /tmp/realtimedb
# Borrar semilla anterior si existe
rm -rf "$BASE_DIR/db_seed/realtimedb"
# Copiar carpeta de dumps
docker cp realtimedb:/tmp/realtimedb "$BASE_DIR/db_seed/"
# Limpiar carpeta temporal en contenedor
docker exec -i realtimedb rm -rf /tmp/realtimedb

echo "¡Dumps guardados en $BASE_DIR/db_seed/!"
echo "Ahora puedes subir la carpeta db_seed/ a tu repositorio Git para empaquetar la práctica."
