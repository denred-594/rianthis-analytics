-- 0. Alle Verbindungen trennen, Datenbank löschen/neu erstellen
DO
$$
BEGIN
   PERFORM pg_terminate_backend(pid) 
   FROM pg_stat_activity 
   WHERE datname = 'rianthis';
END
$$;

DROP DATABASE IF EXISTS rianthis;
CREATE DATABASE rianthis;
\c rianthis;

-- 1. Raw-Tabelle erstellen
DROP TABLE IF EXISTS rianthis_time_entries_raw;

CREATE TABLE rianthis_time_entries_raw (
    user_id BIGINT,
    username TEXT,
    time_entry_id BIGINT,
    description TEXT,
    billable BOOLEAN,
    time_labels TEXT,
    start BIGINT,
    start_text TEXT,
    stop BIGINT,
    stop_text TEXT,
    time_tracked BIGINT,
    time_tracked_text TEXT,
    space_id BIGINT,
    space_name TEXT,
    folder_id BIGINT,
    folder_name TEXT,
    list_id BIGINT,
    list_name TEXT,
    task_id TEXT,
    task_name TEXT,
    task_status TEXT,
    due_date BIGINT,
    due_date_text TEXT,
    start_date BIGINT,
    start_date_text TEXT,
    task_time_estimated BIGINT,
    task_time_estimated_text TEXT,
    task_time_spent BIGINT,
    task_time_spent_text TEXT,
    user_total_time_estimated BIGINT,
    user_total_time_estimated_text TEXT,
    user_total_time_tracked BIGINT,
    user_total_time_tracked_text TEXT,
    tags TEXT,
    checklists TEXT,
    user_period_time_spent BIGINT,
    user_period_time_spent_text TEXT,
    date_created BIGINT,
    date_created_text TEXT,
    custom_task_id TEXT,
    parent_task_id TEXT,
    progress INT,
    phase_dep TEXT
);

-- 2. CSV importieren
COPY rianthis_time_entries_raw FROM '/rianthis_test_data.csv' DELIMITER ',' CSV HEADER;

-- 3. Processed-Tabelle erstellen
DROP TABLE IF EXISTS rianthis_time_entries_processed;

CREATE TABLE rianthis_time_entries_processed AS
SELECT
    NULL::TEXT AS role,
    username,
    description AS description_text,
    list_name,
    task_name,
    billable,
    (time_tracked / 3600000.0) AS time_tracked_hours,
    (task_time_estimated / 3600000.0) AS task_time_estimated_hours,
    (task_time_spent / 3600000.0) AS task_time_spent_hours,
    (user_total_time_tracked / 3600000.0) AS user_total_time_tracked_hours,
    (user_total_time_estimated / 3600000.0) AS user_total_time_estimated_hours,
    EXTRACT(MONTH FROM (to_timestamp(start / 1000) AT TIME ZONE 'Europe/Berlin')) AS month,
    EXTRACT(WEEK FROM (to_timestamp(start / 1000) AT TIME ZONE 'Europe/Berlin')) AS week,
    to_timestamp(start / 1000) AT TIME ZONE 'Europe/Berlin' AS start_timestamp
FROM rianthis_time_entries_raw;

-- Optional: Index für schnellere Auswertungen
CREATE INDEX IF NOT EXISTS idx_time_entries_user_start
ON rianthis_time_entries_processed(username, start_timestamp);

-- 4. Team-Tabelle erstellen
DROP TABLE IF EXISTS rianthis_team_mapping;

CREATE TABLE rianthis_team_mapping (
    username TEXT PRIMARY KEY,
    role TEXT,
    monatsstunden INT
);

-- 5. CSV importieren
COPY rianthis_team_mapping FROM '/rianthis_team_mapping.csv' DELIMITER ',' CSV HEADER;

-- 6. Role nachträglich aktualisieren
ALTER TABLE rianthis_time_entries_processed
ADD COLUMN IF NOT EXISTS role TEXT;

UPDATE rianthis_time_entries_processed p
SET role = t.role
FROM rianthis_team_mapping t
WHERE p.username = t.username;

-- 7. Contract_Info-Tabelle erstellen
DROP TABLE IF EXISTS contract_info;

CREATE TABLE contract_info (
    list_name TEXT,
    customer_type TEXT,
    angebot_h_hours DOUBLE PRECISION,
    vertragsbegin DATE,
    vertragsstunden_hours DOUBLE PRECISION
);

-- 8. Contract_Info CSV importieren als TEXT
CREATE TEMP TABLE contract_info_raw (
    list_name TEXT,
    customer_type TEXT,
    angebot_h TEXT,
    vertragsbegin_text TEXT,
    vertragsstunden TEXT
);

COPY contract_info_raw FROM '/Contract_Info.csv' DELIMITER ',' CSV HEADER;

INSERT INTO contract_info(list_name, customer_type, angebot_h_hours, vertragsbegin, vertragsstunden_hours)
SELECT
    list_name,
    customer_type,
    CASE 
        WHEN angebot_h IS NOT NULL AND angebot_h <> '' THEN
            split_part(angebot_h, ':', 1)::DOUBLE PRECISION +
            split_part(angebot_h, ':', 2)::DOUBLE PRECISION / 60 +
            split_part(angebot_h, ':', 3)::DOUBLE PRECISION / 3600
        ELSE 0
    END,
    CASE 
        WHEN vertragsbegin_text IS NOT NULL AND vertragsbegin_text <> '' THEN
            TO_DATE(vertragsbegin_text, 'DD.MM.YYYY')
        ELSE NULL
    END,
    CASE 
        WHEN vertragsstunden IS NOT NULL AND vertragsstunden <> '' THEN
            split_part(vertragsstunden, ':', 1)::DOUBLE PRECISION +
            split_part(vertragsstunden, ':', 2)::DOUBLE PRECISION / 60 +
            split_part(vertragsstunden, ':', 3)::DOUBLE PRECISION / 3600
        ELSE 0
    END
FROM contract_info_raw;

DROP TABLE contract_info_raw;
