#!/bin/bash
# Creates the MLflow backend database and user in MariaDB (configdb).
set -e
until docker exec configdb mysqladmin ping -h localhost --silent 2>/dev/null; do
    sleep 2
done
docker exec configdb mysql -u root -pchangeIt! -e "
CREATE DATABASE IF NOT EXISTS mlflow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'mlflow'@'%' IDENTIFIED BY 'mlflowpass';
GRANT ALL PRIVILEGES ON mlflow.* TO 'mlflow'@'%';
FLUSH PRIVILEGES;
" 2>/dev/null
