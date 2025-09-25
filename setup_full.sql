-- 0. Alle Verbindungen trennen, Datenbank löschen/neu erstellen
DO
$$
BEGIN
   -- Only terminate connections if the database exists
   IF EXISTS (SELECT 1 FROM pg_database WHERE datname = 'rianthis') THEN
      PERFORM pg_terminate_backend(pid) 
      FROM pg_stat_activity 
      WHERE datname = 'rianthis';
   END IF;
END
$$;

-- Drop and recreate the database
DROP DATABASE IF EXISTS rianthis;
CREATE DATABASE rianthis;
\c rianthis;

-- Disable notice messages to avoid 'table does not exist' warnings
SET client_min_messages TO WARNING;

-- 1. Drop tables if they exist (suppress notice messages)
DO $$
BEGIN
   -- Drop tables in the correct order to respect foreign key constraints
   DROP TABLE IF EXISTS contract_info CASCADE;
   DROP TABLE IF EXISTS rianthis_time_entries_processed CASCADE;
   DROP TABLE IF EXISTS rianthis_team_mapping CASCADE;
   DROP TABLE IF EXISTS rianthis_time_entries_raw CASCADE;
   DROP TABLE IF EXISTS contract_info_raw CASCADE;
EXCEPTION WHEN OTHERS THEN
   -- Ignore any errors during table dropping
   NULL;
END $$;

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

-- 2. Import CSV files using direct paths with proper type handling
\echo 'Importing CSV files...'

-- Create a staging table with text columns to import the raw data
DROP TABLE IF EXISTS rianthis_time_entries_staging;
CREATE TABLE rianthis_time_entries_staging (
    username TEXT,
    description TEXT,
    project TEXT,
    task TEXT,
    billable TEXT,  -- Will be text to accept 'WAHR'/'FALSCH'
    start_date TEXT,
    start_time TEXT,
    end_date TEXT,
    end_time TEXT,
    duration TEXT,
    tags TEXT,
    amount TEXT,
    amount_decimal TEXT,
    amount_formatted TEXT,
    rate_amount TEXT,
    rate_currency_code TEXT,
    rate_amount_decimal TEXT,
    rate_amount_formatted TEXT,
    notes TEXT,
    is_locked TEXT,
    is_billed TEXT,
    is_approved TEXT,
    in_invoice TEXT,
    user_id TEXT,
    user_name TEXT,
    user_email TEXT,
    project_id TEXT,
    project_name TEXT,
    project_color TEXT,
    project_note TEXT,
    client_id TEXT,
    client_name TEXT,
    client_display_name TEXT,
    task_id TEXT,
    task_name TEXT,
    task_estimate_milliseconds TEXT,
    task_status TEXT,
    user_period_time_spent TEXT,
    user_period_time_spent_text TEXT,
    date_created TEXT,
    date_created_text TEXT,
    custom_task_id TEXT,
    parent_task_id TEXT,
    progress TEXT,
    phase_dep TEXT
);

-- Import the CSV into the staging table
\copy rianthis_time_entries_staging FROM '/import/rianthis_test_data.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

-- Now insert into the actual table with proper type conversion
INSERT INTO rianthis_time_entries_raw
SELECT 
    username,
    description,
    project,
    task,
    CASE 
        WHEN billable = 'WAHR' THEN true
        WHEN billable = 'FALSCH' THEN false
        ELSE NULL
    END AS billable,
    start_date,
    start_time,
    end_date,
    end_time,
    duration::bigint,
    tags,
    amount,
    amount_decimal,
    amount_formatted,
    rate_amount,
    rate_currency_code,
    rate_amount_decimal,
    rate_amount_formatted,
    notes,
    is_locked = 'WAHR',
    is_billed = 'WAHR',
    is_approved = 'WAHR',
    in_invoice = 'WAHR',
    user_id,
    user_name,
    user_email,
    project_id,
    project_name,
    project_color,
    project_note,
    client_id,
    client_name,
    client_display_name,
    task_id,
    task_name,
    task_estimate_milliseconds,
    task_status,
    user_period_time_spent::bigint,
    user_period_time_spent_text,
    date_created::bigint,
    date_created_text,
    custom_task_id,
    parent_task_id,
    progress::integer,
    phase_dep
FROM rianthis_time_entries_staging;

-- Drop the staging table
DROP TABLE rianthis_time_entries_staging;

-- Import rianthis_team_mapping.csv
\copy rianthis_team_mapping FROM '/import/rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

-- Import Contract_Info.csv
\copy contract_info_raw FROM '/import/Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

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

-- 5. Team-Mapping importieren
COPY rianthis_team_mapping FROM 'rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"', ESCAPE '\\');

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

COPY contract_info_raw FROM 'Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"', ESCAPE '\\');

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
