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
: "${TEMP_DIR:=/tmp/rianthis_setup}"

# Required files
REQUIRED_FILES=(
  "rianthis_test_data.csv"
  "rianthis_team_mapping.csv"
  "Contract_Info.csv"
  "setup_full.sql"
  "docker-compose.yml"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print messages
info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
  echo -e "${GREEN}✅ $1${NC}"
}

warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

error_exit() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
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
    info "Waiting for database to be ready..."
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
    success "Database is ready!"
}

# Check for required files
MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -ne 0 ]; then
  warning "The following required files are missing:"
  for file in "${MISSING_FILES[@]}"; do
    echo "- ${file}"
  done
  error_exit "Please ensure all required files are in the same directory as this script."
fi

# Main execution
info "Starting Rianthis setup..."

# 1) Start Docker Compose if not running
info "Checking Docker Compose services..."
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_DB}$"; then
  info "Starting Docker Compose services..."
  cd "${SCRIPT_DIR}"
  if ! ${DOCKER_COMPOSE_CMD} up -d --build; then
    error_exit "Failed to start Docker Compose services"
  fi
else
  info "Docker Compose services are already running"
fi

# 2) Wait for database to be ready
wait_for_db

# 3) Copy files to container
info "Copying required files to container..."

# Create a working directory in the container
WORK_DIR="/app"
docker exec ${CONTAINER_DB} mkdir -p ${WORK_DIR} || error_exit "Failed to create working directory in container"

# Copy all required files to the working directory
for file in "rianthis_test_data.csv" "rianthis_team_mapping.csv" "Contract_Info.csv" "setup_full.sql"; do
    info "Copying ${file} to container..."
    docker cp "${SCRIPT_DIR}/${file}" "${CONTAINER_DB}:${WORK_DIR}/${file}" || error_exit "Failed to copy ${file}"
    
    # Verify the file was copied
    if ! docker exec ${CONTAINER_DB} test -f "${WORK_DIR}/${file}"; then
        error_exit "Failed to verify ${file} was copied to container"
    fi
done

# 4) Prepare the SQL script with the correct file paths
info "Preparing SQL script with file paths..."

# Create a temporary file locally
TEMP_SQL="${SCRIPT_DIR}/setup_with_paths.sql"

# Create the schema part (without any file operations)
grep -v '^\\' "${SCRIPT_DIR}/setup_full.sql" > "${TEMP_SQL}.schema"

# Create the data import part
echo "-- Data import part with actual file paths" > "${TEMP_SQL}.data"
echo "\\echo 'Importing CSV files...'" >> "${TEMP_SQL}.data"
echo "" >> "${TEMP_SQL}.data"

# Create a temporary table for time entries with text columns to handle German booleans
echo "-- Create temporary table for time entries" >> "${TEMP_SQL}.data"
echo "CREATE TEMP TABLE temp_time_entries (" >> "${TEMP_SQL}.data"
echo "    id TEXT, user_id TEXT, project_id TEXT, task_id TEXT, billable TEXT, start TEXT, stop TEXT, description TEXT," >> "${TEMP_SQL}.data"
echo "    created_at TEXT, updated_at TEXT, user_name TEXT, project_name TEXT, client_name TEXT" >> "${TEMP_SQL}.data"
echo ") ON COMMIT DROP;" >> "${TEMP_SQL}.data"
echo "" >> "${TEMP_SQL}.data"

# Import into temporary table first
echo "-- Import rianthis_test_data.csv into temporary table" >> "${TEMP_SQL}.data"
echo "\\copy temp_time_entries FROM '/app/rianthis_test_data.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '\"', NULL '');" >> "${TEMP_SQL}.data"
echo "" >> "${TEMP_SQL}.data"

# Transform and insert into the actual table
echo "-- Transform and insert data into the actual table" >> "${TEMP_SQL}.data"
echo "INSERT INTO rianthis_time_entries_raw" >> "${TEMP_SQL}.data"
echo "SELECT" >> "${TEMP_SQL}.data"
echo "    id, user_id, project_id, task_id," >> "${TEMP_SQL}.data"
echo "    CASE WHEN billable = 'WAHR' THEN true WHEN billable = 'FALSCH' THEN false ELSE NULL END as billable," >> "${TEMP_SQL}.data"
echo "    start::timestamp, stop::timestamp, description, created_at::timestamp, updated_at::timestamp," >> "${TEMP_SQL}.data"
echo "    user_name, project_name, client_name" >> "${TEMP_SQL}.data"
echo "FROM temp_time_entries;" >> "${TEMP_SQL}.data"
echo "" >> "${TEMP_SQL}.data"

# Import other CSV files that don't have boolean values
echo "-- Import rianthis_team_mapping.csv" >> "${TEMP_SQL}.data"
echo "\\copy rianthis_team_mapping FROM '/app/rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '\"', NULL '');" >> "${TEMP_SQL}.data"
echo "" >> "${TEMP_SQL}.data"
echo "-- Import Contract_Info.csv" >> "${TEMP_SQL}.data"
echo "\\copy contract_info_raw FROM '/app/Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '\"', NULL '');" >> "${TEMP_SQL}.data"

# Combine both parts
cat "${TEMP_SQL}.schema" "${TEMP_SQL}.data" > "${TEMP_SQL}"
rm -f "${TEMP_SQL}.schema" "${TEMP_SQL}.data"

# Copy the generated SQL file to the container
docker cp "${TEMP_SQL}" "${CONTAINER_DB}:${WORK_DIR}/setup_with_paths.sql"

# 5) Execute the SQL script with detailed error handling
info "Executing SQL script with detailed logging..."

# Create a log file in the container
LOG_FILE="${WORK_DIR}/sql_import.log"

# Execute the SQL script in a single transaction
if ! docker exec -i "${CONTAINER_DB}" bash -c '
    set -euo pipefail
    cd '${WORK_DIR}'
    export PGPASSWORD='${DB_PASSWORD}'
    
    # Start a transaction and execute everything in one go
    echo "BEGIN;" > combined_script.sql
    cat setup_with_paths.sql >> combined_script.sql
    echo "COMMIT;" >> combined_script.sql
    
    # Execute the combined script
    psql -v ON_ERROR_STOP=1 -U '${DB_USER}' -d '${DB_NAME}' -f combined_script.sql
' 2>&1 | tee "${LOG_FILE}"

then
    error_exit "SQL import failed! Showing error log...\n$(docker exec ${CONTAINER_DB} cat "${LOG_FILE}" 2>/dev/null || echo 'Could not retrieve error log')"
fi
"; then
    # If SQL execution failed, show the error log
    error_exit "SQL import failed! Showing error log...\n$(docker exec ${CONTAINER_DB} cat "${LOG_FILE}" 2>/dev/null || echo 'Could not retrieve error log')"
fi

# Verify the SQL executed successfully by checking for common error patterns
if docker exec "${CONTAINER_DB}" grep -q -E 'ERROR|FATAL' "${LOG_FILE}" 2>/dev/null; then
    error_exit "SQL import completed with errors:\n$(docker exec ${CONTAINER_DB} grep -E 'ERROR|FATAL' "${LOG_FILE}" 2>/dev/null || echo 'No detailed error messages found')"
fi

# Clean up temporary files
docker exec ${CONTAINER_DB} rm -rf "${TEMP_DIR}"

# 5) Restart services to apply changes
info "Restarting services to apply changes..."
cd "${SCRIPT_DIR}"
${DOCKER_COMPOSE_CMD} down
${DOCKER_COMPOSE_CMD} up -d

success "Setup completed successfully!"
echo "======================================"
echo "   ✅ Rianthis Setup abgeschlossen!   "
echo "======================================"
echo ""
echo "Zugriff auf die Anwendungen:"
echo "- Metabase: http://localhost:3000"
echo "- PostgreSQL: localhost:5432"
echo ""
echo "Verfügbare Umgebungsvariablen zur Anpassung:"
echo "- CONTAINER_DB: Name des Datenbank-Containers (Standard: metabase_db)"
echo "- DB_USER: Datenbank-Benutzername (Standard: metabase)"
echo "- DB_PASSWORD: Datenbank-Passwort (Standard: metabase)"
echo "- DB_NAME: Datenbank-Name (Standard: metabase)"
echo ""
echo "Beispiel: DB_USER=meinuser DB_PASSWORD=meinpasswort ./setup.sh"

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
