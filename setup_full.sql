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

-- First, let's check the actual structure of the CSV file
-- Create a staging table with a single text column to import the raw data first
DROP TABLE IF EXISTS rianthis_time_entries_staging;
CREATE TABLE rianthis_time_entries_staging (
    line TEXT
);

-- Import the raw data into the staging table
\copy rianthis_time_entries_staging FROM '/import/rianthis_test_data.csv' WITH (FORMAT text);

-- Now create a proper staging table based on the actual CSV structure
DROP TABLE IF EXISTS rianthis_time_entries_staging_parsed;
CREATE TABLE rianthis_time_entries_staging_parsed (
    id TEXT,
    username TEXT,
    description TEXT,
    project TEXT,
    task TEXT,
    billable TEXT,  -- Will be text to accept 'WAHR'/'FALSCH'
    tags TEXT,
    start_date TEXT,
    start_time TEXT,
    end_date TEXT,
    end_time TEXT,
    duration TEXT,
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
    checklists TEXT,
    user_period_time_spent TEXT,
    user_period_time_spent_text TEXT,
    date_created TEXT,
    date_created_text TEXT,
    custom_task_id TEXT,
    parent_task_id TEXT,
    progress TEXT,
    phase_dep TEXT
);

-- Parse the CSV data into the structured table
INSERT INTO rianthis_time_entries_staging_parsed
SELECT 
    split_part(line, ';', 1) AS id,
    split_part(line, ';', 2) AS username,
    split_part(line, ';', 3) AS description,
    split_part(line, ';', 4) AS project,
    split_part(line, ';', 5) AS task,
    split_part(line, ';', 6) AS billable,
    split_part(line, ';', 7) AS tags,
    split_part(line, ';', 8) AS start_date,
    split_part(line, ';', 9) AS start_time,
    split_part(line, ';', 10) AS end_date,
    split_part(line, ';', 11) AS end_time,
    split_part(line, ';', 12) AS duration,
    split_part(line, ';', 13) AS amount,
    split_part(line, ';', 14) AS amount_decimal,
    split_part(line, ';', 15) AS amount_formatted,
    split_part(line, ';', 16) AS rate_amount,
    split_part(line, ';', 17) AS rate_currency_code,
    split_part(line, ';', 18) AS rate_amount_decimal,
    split_part(line, ';', 19) AS rate_amount_formatted,
    split_part(line, ';', 20) AS notes,
    split_part(line, ';', 21) AS is_locked,
    split_part(line, ';', 22) AS is_billed,
    split_part(line, ';', 23) AS is_approved,
    split_part(line, ';', 24) AS in_invoice,
    split_part(line, ';', 25) AS user_id,
    split_part(line, ';', 26) AS user_name,
    split_part(line, ';', 27) AS user_email,
    split_part(line, ';', 28) AS project_id,
    split_part(line, ';', 29) AS project_name,
    split_part(line, ';', 30) AS project_color,
    split_part(line, ';', 31) AS project_note,
    split_part(line, ';', 32) AS client_id,
    split_part(line, ';', 33) AS client_name,
    split_part(line, ';', 34) AS client_display_name,
    split_part(line, ';', 35) AS task_id,
    split_part(line, ';', 36) AS task_name,
    split_part(line, ';', 37) AS task_estimate_milliseconds,
    split_part(line, ';', 38) AS task_status,
    split_part(line, ';', 39) AS checklists,
    split_part(line, ';', 40) AS user_period_time_spent,
    split_part(line, ';', 41) AS user_period_time_spent_text,
    split_part(line, ';', 42) AS date_created,
    split_part(line, ';', 43) AS date_created_text,
    split_part(line, ';', 44) AS custom_task_id,
    split_part(line, ';', 45) AS parent_task_id,
    split_part(line, ';', 46) AS progress,
    split_part(line, ';', 47) AS phase_dep
FROM (
    SELECT line 
    FROM rianthis_time_entries_staging 
    WHERE line NOT LIKE '%username;description;project%'  -- Skip header
) t;

-- Now insert into the actual table with proper type conversion
INSERT INTO rianthis_time_entries_raw (
    user_id, username, description, billable, time_labels, 
    start, start_text, stop, stop_text, time_tracked, 
    time_tracked_text, space_id, space_name, folder_id, folder_name, 
    list_id, list_name, task_id, task_name, task_status, 
    due_date, due_date_text, start_date, start_date_text, task_time_estimated, 
    task_time_estimated_text, task_time_spent, task_time_spent_text, 
    user_total_time_estimated, user_total_time_estimated_text, 
    user_total_time_tracked, user_total_time_tracked_text, tags,
    checklists, user_period_time_spent, user_period_time_spent_text,
    date_created, date_created_text, custom_task_id, parent_task_id,
    progress, phase_dep
)
SELECT 
    CASE WHEN user_id ~ '^[0-9]+$' THEN user_id::bigint ELSE NULL END,
    username,
    description,
    CASE 
        WHEN billable = 'WAHR' THEN true
        WHEN billable = 'FALSCH' THEN false
        ELSE NULL
    END AS billable,
    NULL, -- time_labels
    NULL, -- start
    NULL, -- start_text
    NULL, -- stop
    NULL, -- stop_text
    CASE WHEN duration ~ '^[0-9]+$' THEN duration::bigint ELSE NULL END, -- time_tracked
    NULL, -- time_tracked_text
    NULL, -- space_id
    NULL, -- space_name
    NULL, -- folder_id
    NULL, -- folder_name
    NULL, -- list_id
    NULL, -- list_name (not in source data)
    task_id,
    task_name,
    task_status,
    NULL, -- due_date
    NULL, -- due_date_text
    CASE WHEN start_date ~ '^[0-9]+$' THEN start_date::bigint ELSE NULL END, -- start_date
    NULL, -- start_date_text
    CASE WHEN task_estimate_milliseconds ~ '^[0-9]+$' THEN task_estimate_milliseconds::bigint ELSE NULL END, -- task_time_estimated
    NULL, -- task_time_estimated_text
    NULL, -- task_time_spent
    NULL, -- task_time_spent_text
    NULL, -- user_total_time_estimated
    NULL, -- user_total_time_estimated_text
    NULL, -- user_total_time_tracked
    NULL, -- user_total_time_tracked_text
    tags,
    checklists,
    CASE WHEN user_period_time_spent ~ '^[0-9]+$' THEN user_period_time_spent::bigint ELSE NULL END,
    user_period_time_spent_text,
    CASE WHEN date_created ~ '^[0-9]+$' THEN date_created::bigint ELSE NULL END,
    date_created_text,
    custom_task_id,
    parent_task_id,
    CASE WHEN progress ~ '^[0-9]+$' THEN progress::integer ELSE NULL END,
    phase_dep
FROM rianthis_time_entries_staging_parsed;

-- Drop the staging tables
DROP TABLE rianthis_time_entries_staging;
DROP TABLE rianthis_time_entries_staging_parsed;

-- 3. Create and populate rianthis_team_mapping table
DROP TABLE IF EXISTS rianthis_team_mapping;

CREATE TABLE rianthis_team_mapping (
    username TEXT PRIMARY KEY,
    role TEXT,
    monatsstunden INT
);

-- Import rianthis_team_mapping.csv
\copy rianthis_team_mapping FROM '/import/rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

-- 4. Create and populate contract_info_raw table
DROP TABLE IF EXISTS contract_info_raw;

CREATE TABLE contract_info_raw (
    list_name TEXT,
    customer_type TEXT,
    angebot_per_hour TEXT,
    vertragsbegin TEXT,
    vertragsstunden TEXT
);

-- Import Contract_Info.csv
\copy contract_info_raw FROM '/import/Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

-- 3. Create processed time entries table
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

-- 7. Process contract info
DROP TABLE IF EXISTS contract_info;

CREATE TABLE contract_info AS
SELECT 
    list_name,
    customer_type,
    angebot_per_hour,
    vertragsbegin,
    vertragsstunden
FROM contract_info_raw;

-- 8. Clean up temporary tables
DROP TABLE IF EXISTS contract_info_raw;

-- 7. Role nachträglich aktualisieren
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

-- Import using \copy with the correct container path
\copy contract_info_raw FROM '/import/Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

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
