#!/bin/bash

# Colores para salida estándar
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
BOLD='\033[1m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${RED}${BOLD}Deteniendo todos los módulos de OnesaitPlatform...${NC}"

# 1. Detener todos los módulos en op_modules
for dir in "$BASE_DIR"/op_modules/*; do
    if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
        module_name=$(basename "$dir")
        echo -e "Deteniendo módulo: ${BOLD}$module_name${NC}..."
        cd "$dir" && docker compose down
    fi
done

# 2. Detener la capa de persistencia (bases de datos)
echo -e "\n${RED}${BOLD}Deteniendo bases de datos (op_data)...${NC}"
cd "$BASE_DIR/op_data" && docker compose -f docker-compose.persistent.yml down

echo -e "\n${GREEN}${BOLD}¡Todo el entorno de OnesaitPlatform ha sido detenido con éxito!${NC}"
