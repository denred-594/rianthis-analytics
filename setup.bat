@echo off
REM ======================================
REM Rianthis Full Setup Script (.bat)
REM ======================================

REM 1. CSV-Dateien ins Docker-Container kopieren
docker cp "/Users/dennyredel/Documents/Metabase/rianthis_test_data.csv" metabase_db:/rianthis_test_data.csv
docker cp "/Users/dennyredel/Documents/Metabase/rianthis_team_mapping.csv" metabase_db:/rianthis_team_mapping.csv
docker cp "/Users/dennyredel/Documents/Metabase/Contract_Info.csv" metabase_db:/Contract_Info.csv

REM 2. SQL-Skript ins Docker-Container kopieren und ausführen
docker cp "/Users/dennyredel/Documents/Metabase/setup_full.sql" metabase_db:/setup_full.sql
docker exec -it metabase_db psql -U metabase -d postgres -f /setup_full.sql

REM 3. Docker-Compose neu starten
docker compose down
docker-compose up -d

pause
