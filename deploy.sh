#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
BLUE='\033[0;34m'
BOLD='\033[1m'

clear
echo -e "${BLUE}${BOLD}========================================================"
echo -e "      OnesaitPlatform - Student Environment Deployer    "
echo -e "========================================================${NC}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OP_DATA_DIR="$BASE_DIR/op_data"
NGINX_DIR="$BASE_DIR/op_modules/nginx-proxy"

# 1. Configurar SERVER_NAME (auto-detecta la IP de WSL2/host como default)
WSL_IP=$(hostname -I | awk '{print $1}')
read -p "Ingresa el SERVER_NAME para el despliegue [default: $WSL_IP]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-$WSL_IP}
echo -e "${GREEN}Configurando SERVER_NAME=$SERVER_NAME...${NC}"

find "$BASE_DIR" -name ".env" -type f -exec sed -i "s/^SERVER_NAME=.*/SERVER_NAME=$SERVER_NAME/g" {} +

# 2. Selección de Perfil
echo -e "\n${BOLD}Selecciona el perfil de tu grupo de trabajo:${NC}"
echo -e "1) ${BOLD}Completo / Profesor${NC} (Todos los módulos - Requiere >12GB RAM)"
echo -e "2) ${BOLD}Integración de Datos${NC} (Anyi y Fernando - DBs, Control Panel, Keycloak, Dataflow, FlowEngine, IoT/APIs)"
echo -e "3) ${BOLD}Reporting y Negocio${NC} (Wesfalia, Kevin y Pamela - DBs, Control Panel, Keycloak, DashboardEngine)"
echo -e "4) ${BOLD}Analítica Predictiva${NC} (Isaías - DBs, Control Panel, Keycloak, Notebooks)"
read -p "Opción [1-4]: " PROFILE_OPT

case $PROFILE_OPT in
    1)
        PROFILE="FULL"
        MODULES=("keycloak" "mlops-manager" "control-panel" "keycloak-manager" "router" "iotbroker" "api-manager" "flowengine" "dataflow" "dashboard-engine" "notebooks" "nginx-proxy")
        ;;
    2)
        PROFILE="INTEGRATION"
        MODULES=("keycloak" "mlops-manager" "control-panel" "keycloak-manager" "router" "iotbroker" "api-manager" "flowengine" "dataflow" "nginx-proxy")
        ;;
    3)
        PROFILE="REPORTING"
        MODULES=("keycloak" "mlops-manager" "control-panel" "keycloak-manager" "dashboard-engine" "nginx-proxy")
        ;;
    4)
        PROFILE="ANALYTICS"
        MODULES=("keycloak" "mlops-manager" "control-panel" "keycloak-manager" "notebooks" "nginx-proxy")
        ;;
    *)
        echo -e "${RED}Opción inválida. Saliendo...${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Perfil seleccionado: $PROFILE${NC}"

# Guardar perfil activo para start.sh
echo "PROFILE=$PROFILE" > "$BASE_DIR/.profile"
echo "MODULES=\"${MODULES[*]}\"" >> "$BASE_DIR/.profile"

# 3. Generación de Certificados SSL autofirmados (siempre en deploy para reflejar SERVER_NAME actual)
echo -e "\n${YELLOW}Generando certificados SSL autofirmados para $SERVER_NAME...${NC}"
sed -i "s/export COMMONNAME=.*/export COMMONNAME=\"$SERVER_NAME\"/g" "$NGINX_DIR/generate_certificates.sh"
cd "$NGINX_DIR" && chmod +x generate_certificates.sh && ./generate_certificates.sh
cd "$BASE_DIR"

# 4. Crear directorios de persistencia local y otorgar permisos
echo -e "\n${GREEN}Creando directorios de persistencia local y asignando permisos 777...${NC}"
mkdir -p "$OP_DATA_DIR/data/mongodb"
mkdir -p "$OP_DATA_DIR/data/mariadb"
chmod -R 777 "$OP_DATA_DIR/data" 2>/dev/null || true

# 5. Levantar bases de datos
echo -e "\n${GREEN}Iniciando bases de datos (MariaDB y MongoDB)...${NC}"
cd "$OP_DATA_DIR"
docker compose -f docker-compose.persistent.yml up -d
cd "$BASE_DIR"

# Detectar IP del bridge de Docker para control-panel extra_hosts
echo -e "${YELLOW}Detectando IP del bridge de Docker...${NC}"
DOCKER_BRIDGE_IP=$(docker network inspect op_data_datanetwork --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null)
if [ -z "$DOCKER_BRIDGE_IP" ]; then
    DOCKER_BRIDGE_IP="172.28.0.1"
    echo -e "${YELLOW}No se pudo detectar la IP del bridge, usando default: $DOCKER_BRIDGE_IP${NC}"
else
    echo -e "${GREEN}IP del bridge de Docker: $DOCKER_BRIDGE_IP${NC}"
fi
sed -i "s/^IP=.*/IP=$DOCKER_BRIDGE_IP/g" "$BASE_DIR/op_modules/control-panel/.env"

# 6. Esperar a que las bases de datos respondan
echo -e "\n${YELLOW}Esperando a que las bases de datos estén listas...${NC}"
until docker exec configdb mysqladmin ping -h localhost --silent 2>/dev/null; do
    echo "Esperando a configdb (MariaDB)..."
    sleep 2
done
echo -e "${GREEN}configdb está lista.${NC}"

until docker exec realtimedb mongosh --eval 'db.adminCommand({ping: 1})' --quiet &>/dev/null; do
    echo "Esperando a realtimedb (MongoDB)..."
    sleep 2
done
echo -e "${GREEN}realtimedb está lista.${NC}"

# 7. Inicialización de Datos en primera ejecución
INIT_FLAG="$OP_DATA_DIR/data/.initialized"
if [ ! -f "$INIT_FLAG" ]; then
    echo -e "\n${YELLOW}Primera ejecución detectada. Inicializando base de datos de OnesaitPlatform...${NC}"

    docker rm -f configinitservice 2>/dev/null || true
    cd "$OP_DATA_DIR"
    docker compose -f docker-compose.initdb.yml down 2>/dev/null || true
    docker compose -f docker-compose.initdb.yml up --abort-on-container-exit
    cd "$BASE_DIR"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Base de datos inicializada correctamente.${NC}"
        touch "$INIT_FLAG"
    else
        echo -e "${RED}Error al inicializar la base de datos.${NC}"
        exit 1
    fi
fi

# Ejecutar script de restauración/seed
if [ -f "$BASE_DIR/restore.sh" ]; then
    echo -e "\n${YELLOW}Ejecutando script de restauración/configuración de usuarios...${NC}"
    chmod +x "$BASE_DIR/restore.sh"
    "$BASE_DIR/restore.sh"
fi

# Sincronizar ADMIN_API_KEY y PLATFORM_ADMIN_APIKEY desde la DB
echo -e "\n${YELLOW}Sincronizando API Keys de administración desde la base de datos...${NC}"
PLATFORM_ADMIN_TOKEN=""
for i in {1..10}; do
    PLATFORM_ADMIN_TOKEN=$(docker exec -i configdb mysql -u root -pchangeIt! onesaitplatform_config -N -B -e "SELECT token FROM user_token WHERE user_id='platform_admin';" 2>/dev/null | tr -d '\r\n ')
    if [ -n "$PLATFORM_ADMIN_TOKEN" ]; then
        echo -e "${GREEN}Token obtenido: $PLATFORM_ADMIN_TOKEN${NC}"
        sed -i "s/^PLATFORM_ADMIN_APIKEY=.*/PLATFORM_ADMIN_APIKEY=$PLATFORM_ADMIN_TOKEN/g" "$BASE_DIR/op_modules/keycloak-manager/.env"
        sed -i "s/^ADMIN_API_KEY=.*/ADMIN_API_KEY=$PLATFORM_ADMIN_TOKEN/g" "$BASE_DIR/op_modules/control-panel/.env"
        break
    fi
    echo "Esperando token de platform_admin... ($i/10)"
    sleep 2
done

if [ -z "$PLATFORM_ADMIN_TOKEN" ]; then
    echo -e "${YELLOW}Advertencia: no se pudo obtener el token de platform_admin. Los módulos pueden tener problemas de autenticación.${NC}"
fi

# 8. Configurar nginx.conf dinámicamente basado en los módulos activos
echo -e "\n${GREEN}Configurando Nginx Proxy para el perfil $PROFILE...${NC}"
cp "$NGINX_DIR/conf.d/nginx.conf.template" "$NGINX_DIR/conf.d/nginx.conf"

uncomment_include() {
    local conf_name=$1
    sed -i "s|#include /usr/local/conf.d/$conf_name;|include /usr/local/conf.d/$conf_name;|g" "$NGINX_DIR/conf.d/nginx.conf"
}

uncomment_include "keycloak.conf"

if [[ " ${MODULES[@]} " =~ " dashboard-engine " ]]; then uncomment_include "dashboardengine.conf"; fi
if [[ " ${MODULES[@]} " =~ " notebooks " ]]; then uncomment_include "notebook.conf"; fi
if [[ " ${MODULES[@]} " =~ " flowengine " ]]; then uncomment_include "flowengine.conf"; fi
if [[ " ${MODULES[@]} " =~ " api-manager " ]]; then
    uncomment_include "apimanager.conf"
    uncomment_include "digitalbroker.conf"
    uncomment_include "router.conf"
fi

sed -i "s/server_name \${SERVER_NAME};/server_name $SERVER_NAME;/g" "$NGINX_DIR/conf.d/nginx.conf"

# 9. Levantar módulos de la aplicación
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
echo -e "  ¡El entorno de OnesaitPlatform ha sido iniciado!       "
echo -e "========================================================${NC}"
echo -e "Perfil: ${BOLD}$PROFILE${NC}"
echo -e "Accede en: ${BOLD}https://$SERVER_NAME/controlpanel/${NC}"
echo -e "Revisa INSTRUCTIONS.md para conocer las credenciales de los estudiantes."
