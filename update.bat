@echo off
SETLOCAL

REM Pfade anpassen
SET CONTAINER_NAME=metabase_db
SET DB_NAME=rianthis
SET SQL_SCRIPT=C:\Users\levin\Documents\Rianthis\Metabase\update_team_contract.sql
SET TEAM_CSV=C:\Users\levin\Documents\Rianthis\Metabase\rianthis_team_mapping.csv
SET CONTRACT_CSV=C:\Users\levin\Documents\Rianthis\Metabase\Contract_Info.csv

echo -------------------------------
echo CSVs in Container kopieren...
docker cp "%TEAM_CSV%" %CONTAINER_NAME%:/team_mapping.csv
docker cp "%CONTRACT_CSV%" %CONTAINER_NAME%:/contract_info.csv

echo -------------------------------
echo SQL-Skript in Container kopieren...
docker cp "%SQL_SCRIPT%" %CONTAINER_NAME%:/update_team_contract.sql

echo -------------------------------
echo Skript ausführen...
docker exec -i %CONTAINER_NAME% psql -U metabase -d %DB_NAME% -f /update_team_contract.sql
IF %ERRORLEVEL% NEQ 0 (
    echo FEHLER: SQL-Skript konnte nicht erfolgreich ausgeführt werden!
    exit /b 1
)

echo -------------------------------
echo Optional: Container neu starten...
docker-compose down
docker-compose up -d

echo -------------------------------
echo Fertig! Tabellen wurden aktualisiert.
pause
