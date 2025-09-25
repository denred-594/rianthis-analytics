#!/usr/bin/env bash
set -euo pipefail

# ======================================
# Rianthis Full Setup Script (Linux/macOS)
# ======================================

# KONFIG: Pfade auf deinem Linux/Mac anpassen
CSV_DIR="/home/denny/Documents/Metabase"
SQL_FILE="${CSV_DIR}/setup_full.sql"
CONTAINER_DB="metabase_db"
DB_USER="metabase"
DB_NAME="postgres"

# 1) CSV-Dateien ins Docker-Container kopieren
docker cp "${CSV_DIR}/rianthis_test_data.csv" "${CONTAINER_DB}:/rianthis_test_data.csv"
docker cp "${CSV_DIR}/rianthis_team_mapping.csv" "${CONTAINER_DB}:/rianthis_team_mapping.csv"
docker cp "${CSV_DIR}/Contract_Info.csv"        "${CONTAINER_DB}:/Contract_Info.csv"

# 2) SQL-Skript ins Docker-Container kopieren und ausführen
docker cp "${SQL_FILE}" "${CONTAINER_DB}:/setup_full.sql"
docker exec -i "${CONTAINER_DB}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /setup_full.sql

# 3) Docker-Compose neu starten
# Hinweis: je nach Installation 'docker compose' oder 'docker-compose'
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
