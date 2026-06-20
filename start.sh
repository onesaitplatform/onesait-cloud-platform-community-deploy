#!/bin/bash
# Day-to-day restart script. Run this after stopping containers or after a WSL2 reboot.
# The WSL2 IP changes on each reboot — this script detects the new IP and reconfigures everything.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
BLUE='\033[0;34m'
BOLD='\033[1m'

clear
echo -e "${BLUE}${BOLD}========================================================"
echo -e "      OnesaitPlatform - Start (reinicio rápido)         "
echo -e "========================================================${NC}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OP_DATA_DIR="$BASE_DIR/op_data"
NGINX_DIR="$BASE_DIR/op_modules/nginx-proxy"
PROFILE_FILE="$BASE_DIR/.profile"

# Cargar perfil guardado por deploy.sh
if [ ! -f "$PROFILE_FILE" ]; then
    echo -e "${RED}No se encontró el perfil (.profile). Ejecuta deploy.sh primero.${NC}"
    exit 1
fi

source "$PROFILE_FILE"
MODULES=($MODULES)

echo -e "${GREEN}Perfil: $PROFILE | Módulos: ${MODULES[*]}${NC}"

# 1. Detectar IP actual de WSL2 (cambia en cada reinicio de WSL)
SERVER_NAME=$(hostname -I | awk '{print $1}')
echo -e "\n${YELLOW}IP actual de WSL2: $SERVER_NAME${NC}"

# Leer SERVER_NAME anterior desde control-panel .env
OLD_SERVER_NAME=$(grep "^SERVER_NAME=" "$BASE_DIR/op_modules/control-panel/.env" 2>/dev/null | cut -d= -f2)

echo -e "${GREEN}Actualizando SERVER_NAME=$SERVER_NAME en todos los módulos...${NC}"
find "$BASE_DIR" -name ".env" -type f -exec sed -i "s/^SERVER_NAME=.*/SERVER_NAME=$SERVER_NAME/g" {} +

# 2. Levantar bases de datos
echo -e "\n${GREEN}Iniciando bases de datos (MariaDB y MongoDB)...${NC}"
cd "$OP_DATA_DIR"
docker compose -f docker-compose.persistent.yml up -d
cd "$BASE_DIR"

# Detectar IP del bridge de Docker para control-panel extra_hosts
DOCKER_BRIDGE_IP=$(docker network inspect op_data_datanetwork --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null)
if [ -z "$DOCKER_BRIDGE_IP" ]; then
    DOCKER_BRIDGE_IP="172.28.0.1"
fi
echo -e "${GREEN}IP del bridge de Docker: $DOCKER_BRIDGE_IP${NC}"
sed -i "s/^IP=.*/IP=$DOCKER_BRIDGE_IP/g" "$BASE_DIR/op_modules/control-panel/.env"

# 3. Regenerar certificados SSL si cambió el SERVER_NAME
if [ "$SERVER_NAME" != "$OLD_SERVER_NAME" ]; then
    echo -e "\n${YELLOW}SERVER_NAME cambió ($OLD_SERVER_NAME → $SERVER_NAME). Regenerando certificados SSL...${NC}"
    sed -i "s/export COMMONNAME=.*/export COMMONNAME=\"$SERVER_NAME\"/g" "$NGINX_DIR/generate_certificates.sh"
    cd "$NGINX_DIR" && chmod +x generate_certificates.sh && ./generate_certificates.sh
    cd "$BASE_DIR"
fi

# 4. Esperar bases de datos
echo -e "\n${YELLOW}Esperando a que las bases de datos estén listas...${NC}"
until docker exec configdb mysqladmin ping -h localhost --silent 2>/dev/null; do
    echo "Esperando a configdb (MariaDB)..."
    sleep 2
done
echo -e "${GREEN}configdb lista.${NC}"

until docker exec realtimedb mongosh --eval 'db.adminCommand({ping: 1})' --quiet &>/dev/null; do
    echo "Esperando a realtimedb (MongoDB)..."
    sleep 2
done
echo -e "${GREEN}realtimedb lista.${NC}"

# 5. Sincronizar API Keys desde la DB
echo -e "\n${YELLOW}Sincronizando API Keys desde la base de datos...${NC}"
for i in {1..10}; do
    PLATFORM_ADMIN_TOKEN=$(docker exec -i configdb mysql -u root -pchangeIt! onesaitplatform_config -N -B -e "SELECT token FROM user_token WHERE user_id='platform_admin';" 2>/dev/null | tr -d '\r\n ')
    if [ -n "$PLATFORM_ADMIN_TOKEN" ]; then
        sed -i "s/^PLATFORM_ADMIN_APIKEY=.*/PLATFORM_ADMIN_APIKEY=$PLATFORM_ADMIN_TOKEN/g" "$BASE_DIR/op_modules/keycloak-manager/.env"
        sed -i "s/^ADMIN_API_KEY=.*/ADMIN_API_KEY=$PLATFORM_ADMIN_TOKEN/g" "$BASE_DIR/op_modules/control-panel/.env"
        echo -e "${GREEN}API Keys sincronizadas.${NC}"
        break
    fi
    echo "Esperando token de platform_admin... ($i/10)"
    sleep 2
done

# 6. Reconstruir nginx.conf desde template con SERVER_NAME y módulos activos
echo -e "\n${GREEN}Reconfigurando Nginx para el perfil $PROFILE...${NC}"
cp "$NGINX_DIR/conf.d/nginx.conf.template" "$NGINX_DIR/conf.d/nginx.conf"

uncomment_include() {
    local conf_name=$1
    sed -i "s|#include /usr/local/conf.d/$conf_name;|include /usr/local/conf.d/$conf_name;|g" "$NGINX_DIR/conf.d/nginx.conf"
}

uncomment_include "keycloak.conf"
if [[ " ${MODULES[@]} " =~ " dashboard-engine " ]]; then uncomment_include "dashboardengine.conf"; fi
if [[ " ${MODULES[@]} " =~ " notebooks " ]]; then uncomment_include "notebook.conf"; fi
if [[ " ${MODULES[@]} " =~ " flowengine " ]]; then uncomment_include "flowengine.conf"; fi
if [[ " ${MODULES[@]} " =~ " mlops-manager " ]]; then uncomment_include "mlflow.conf"; fi
if [[ " ${MODULES[@]} " =~ " api-manager " ]]; then
    uncomment_include "apimanager.conf"
    uncomment_include "digitalbroker.conf"
    uncomment_include "router.conf"
fi

sed -i "s/server_name \${SERVER_NAME};/server_name $SERVER_NAME;/g" "$NGINX_DIR/conf.d/nginx.conf"

# Forzar sincronización del nginx.conf en el contenedor (WSL2 bind mount lag)
if docker ps -q --filter name=proxy | grep -q .; then
    docker exec proxy sh -c "
        awk '{gsub(\"#include /usr/local/conf.d/notebook.conf;\",\"include /usr/local/conf.d/notebook.conf;\")}1' /etc/nginx/nginx.conf > /tmp/nginx_sync.conf && cat /tmp/nginx_sync.conf > /etc/nginx/nginx.conf
        awk '{gsub(\"#include /usr/local/conf.d/mlflow.conf;\",\"include /usr/local/conf.d/mlflow.conf;\")}1' /etc/nginx/nginx.conf > /tmp/nginx_sync.conf && cat /tmp/nginx_sync.conf > /etc/nginx/nginx.conf
        nginx -t && nginx -s reload
    " 2>/dev/null && echo -e \"${GREEN}Nginx sincronizado y recargado.${NC}\"
    # Copy any new conf files that WSL2 bind mount hasn't propagated yet
    for conf in notebook mlflow; do
        if [ -f \"$NGINX_DIR/conf.d/\${conf}.conf\" ]; then
            docker cp \"$NGINX_DIR/conf.d/\${conf}.conf\" proxy:/usr/local/conf.d/\${conf}.conf 2>/dev/null || true
        fi
    done
fi

# 7. Iniciar módulos
if [[ " ${MODULES[*]} " =~ " mlops-manager " ]]; then
    echo -e "\n${YELLOW}Inicializando base de datos MLflow...${NC}"
    chmod +x "$BASE_DIR/scripts/init-mlflow-db.sh"
    "$BASE_DIR/scripts/init-mlflow-db.sh"
fi

echo -e "\n${GREEN}Iniciando módulos para el perfil $PROFILE...${NC}"
for module in "${MODULES[@]}"; do
    echo -e "${YELLOW}Iniciando módulo: $module...${NC}"
    cd "$BASE_DIR/op_modules/$module"
    docker compose up -d
done

cd "$BASE_DIR"

echo -e "\n${GREEN}${BOLD}========================================================"
echo -e "  ¡OnesaitPlatform está arriba!                          "
echo -e "========================================================${NC}"
echo -e "Perfil: ${BOLD}$PROFILE${NC}"
echo -e "Accede en: ${BOLD}https://$SERVER_NAME/controlpanel/${NC}"
