#!/usr/bin/env bash
set -euo pipefail

# ======================================
# Rianthis Full Setup Script (Linux/macOS)
# ======================================

# Script directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration - can be overridden by environment variables
: "${CONTAINER_DB:=metabase_db}"
: "${DB_USER:=metabase}"
: "${DB_PASSWORD:=metabase}"
: "${DB_NAME:=metabase}"
: "${DOCKER_COMPOSE_CMD:=$(command -v docker-compose || echo "docker compose")}"

# Required files
REQUIRED_FILES=(
  "rianthis_test_data.csv"
  "rianthis_team_mapping.csv"
  "Contract_Info.csv"
  "setup_full.sql"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print error messages
error_exit() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if Docker is installed and running
if ! command_exists docker; then
  error_exit "Docker is not installed. Please install Docker and try again."
fi

if ! docker info >/dev/null 2>&1; then
  error_exit "Docker daemon is not running. Please start Docker and try again."
fi

# Function to wait for database to be ready
wait_for_db() {
    echo -e "${YELLOW}Waiting for database to be ready...${NC}"
    local timeout=60
    local start_time=$(date +%s)
    
    while ! docker exec -i "${CONTAINER_DB}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -ge $timeout ]; then
            error_exit "Timeout waiting for database to be ready"
        fi
        
        echo -n "."
        sleep 2
    done
    echo -e "\n${GREEN}Database is ready!${NC}"
}

# Check for required files
MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -ne 0 ]; then
  echo -e "${YELLOW}Warning: The following required files are missing:${NC}"
  for file in "${MISSING_FILES[@]}"; do
    echo "- ${file}"
  done
  error_exit "Please ensure all required files are in the same directory as this script."
fi

echo -e "${GREEN}Starting setup...${NC}"

# 1) Wait for database to be ready
wait_for_db

# 2) Copy CSV files to Docker container
echo -e "${YELLOW}Copying CSV files to container...${NC}"
docker cp "${SCRIPT_DIR}/rianthis_test_data.csv" "${CONTAINER_DB}:/rianthis_test_data.csv" || error_exit "Failed to copy rianthis_test_data.csv"
docker cp "${SCRIPT_DIR}/rianthis_team_mapping.csv" "${CONTAINER_DB}:/rianthis_team_mapping.csv" || error_exit "Failed to copy rianthis_team_mapping.csv"
docker cp "${SCRIPT_DIR}/Contract_Info.csv" "${CONTAINER_DB}:/Contract_Info.csv" || error_exit "Failed to copy Contract_Info.csv"

# 3) Copy and execute SQL script
echo -e "${YELLOW}Copying and executing SQL script...${NC}"
docker cp "${SCRIPT_DIR}/setup_full.sql" "${CONTAINER_DB}:/setup_full.sql" || error_exit "Failed to copy setup_full.sql"

if ! docker exec -i "${CONTAINER_DB}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /setup_full.sql; then
  error_exit "SQL import failed!"
fi

# 3) Restart Docker Compose
echo -e "${YELLOW}Restarting Docker Compose...${NC}"
if docker compose version >/dev/null 2>&1; then
  docker compose down
  docker compose up -d
else
  docker-compose down
  docker-compose up -d
fi

echo "Fertig: Daten kopiert, SQL ausgeführt, Services neu gestartet."
#!/bin/bash

set -e  # Script sofort abbrechen bei Fehlern
set -o pipefail

echo "======================================"
echo "   Rianthis Full Setup Script (.sh)"
echo "======================================"

# Pfade zu den Dateien
BASE_DIR="$HOME/Documents/Metabase"
CSV1="$BASE_DIR/rianthis_test_data.csv"
CSV2="$BASE_DIR/rianthis_team_mapping.csv"
CSV3="$BASE_DIR/Contract_Info.csv"
SQL="$BASE_DIR/setup_full.sql"

# Name des DB-Containers
DB_CONTAINER="metabase_db"
DB_USER="metabase"
DB_NAME="postgres"

# --------------------------------------
# 1. Prüfen, ob Docker läuft
# --------------------------------------
if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker läuft nicht. Bitte starte Docker Desktop oder den Docker Daemon!"
  exit 1
fi

# --------------------------------------
# 2. Prüfen, ob Container existiert
# --------------------------------------
if ! docker ps -a --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
  echo "⚠️  Container '${DB_CONTAINER}' existiert nicht. Starte Docker Compose ..."
  docker compose up -d --build
fi

# --------------------------------------
# 3. Warten, bis der Container läuft
# --------------------------------------
echo "⏳ Warte, bis '${DB_CONTAINER}' bereit ist..."

for i in {1..30}; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "notfound")
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "unknown")

    if [[ "$STATUS" == "running" && "$HEALTH" == "healthy" ]]; then
        echo "✅ Container '${DB_CONTAINER}' ist bereit!"
        break
    fi

    if [[ "$STATUS" == "restarting" ]]; then
        echo "❌ Container '${DB_CONTAINER}' hängt in einer Restart-Schleife!"
        echo "   → Wahrscheinlich ist das Datenbank-Volume beschädigt."
        echo "   → Lösung: 'docker compose down --volumes --remove-orphans' und dann neu starten."
        exit 1
    fi

    echo "⌛ Status: $STATUS / Health: $HEALTH ... versuche erneut ($i/30)"
    sleep 3
done

# Prüfen, ob Container nach Timeout läuft
if [[ "$(docker inspect --format='{{.State.Status}}' "$DB_CONTAINER")" != "running" ]]; then
    echo "❌ Container '${DB_CONTAINER}' konnte nicht gestartet werden."
    exit 1
fi

# --------------------------------------
# 4. CSV-Dateien kopieren
# --------------------------------------
echo "📂 Kopiere CSV-Dateien in den Container ..."
docker cp "$CSV1" "$DB_CONTAINER:/rianthis_test_data.csv"
docker cp "$CSV2" "$DB_CONTAINER:/rianthis_team_mapping.csv"
docker cp "$CSV3" "$DB_CONTAINER:/Contract_Info.csv"

# --------------------------------------
# 5. SQL-Skript kopieren & ausführen
# --------------------------------------
echo "📜 Kopiere und importiere SQL-Skript ..."
docker cp "$SQL" "$DB_CONTAINER:/setup_full.sql"

if ! docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -f /setup_full.sql; then
    echo "❌ SQL-Import fehlgeschlagen!"
    exit 1
fi

echo "✅ SQL-Import erfolgreich abgeschlossen!"

# --------------------------------------
# 6. Docker Compose neu starten
# --------------------------------------
echo "🔄 Starte Docker Compose neu ..."
docker compose down
docker compose up -d --build

echo "======================================"
echo "   ✅ Setup erfolgreich abgeschlossen!"
echo "======================================"
