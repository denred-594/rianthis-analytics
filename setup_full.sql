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

-- Set the import directory from environment variable or use default
\set import_dir `echo "${IMPORT_DIR:-/tmp}"`
\echo 'Importing data from directory: ' :'import_dir'

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

-- 2. Create a temporary table with text columns to import the raw data
CREATE TABLE rianthis_time_entries_raw_text (
    user_id TEXT,
    username TEXT,
    time_entry_id TEXT,
    description TEXT,
    billable TEXT,  -- Will be converted from 'WAHR'/'FALSCH' to boolean
    time_labels TEXT,
    start TEXT,
    start_text TEXT,
    stop TEXT,
    stop_text TEXT,
    time_tracked TEXT,
    time_tracked_text TEXT,
    space_id TEXT,
    space_name TEXT,
    folder_id TEXT,
    folder_name TEXT,
    list_id TEXT,
    list_name TEXT,
    task_id TEXT,
    task_name TEXT,
    task_status TEXT,
    due_date TEXT,
    due_date_text TEXT,
    start_date TEXT,
    start_date_text TEXT,
    task_time_estimated TEXT,
    task_time_estimated_text TEXT,
    task_time_spent TEXT,
    task_time_spent_text TEXT,
    user_total_time_estimated TEXT,
    user_total_time_estimated_text TEXT,
    user_total_time_tracked TEXT,
    user_total_time_tracked_text TEXT,
    tags TEXT,
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

-- 3. Import CSV files using direct paths
\echo 'Importing rianthis_test_data.csv'
\copy rianthis_time_entries_raw_text FROM '/import/rianthis_test_data.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

-- 4. Convert the text data to the final table with proper types
-- First, create a function to convert scientific notation with comma to numeric
CREATE OR REPLACE FUNCTION convert_scientific(text) RETURNS TEXT AS $$
DECLARE
    num_text TEXT;
    base_part TEXT;
    exp_part TEXT;
    base_num NUMERIC;
    exp_num INTEGER;
    result TEXT;
BEGIN
    -- Handle empty strings
    IF $1 IS NULL OR $1 = '' THEN
        RETURN NULL;
    END IF;
    
    -- Remove any whitespace
    num_text := TRIM($1);
    
    -- Check if it's in scientific notation with comma
    IF num_text ~* '^[0-9,]+[eE][+-]?[0-9]+$' THEN
        -- Split into base and exponent
        base_part := SPLIT_PART(UPPER(num_text), 'E', 1);
        exp_part := SPLIT_PART(UPPER(num_text), 'E', 2);
        
        -- Replace comma with dot and convert to numeric
        base_num := REPLACE(base_part, ',', '.')::NUMERIC;
        exp_num := exp_part::INTEGER;
        
        -- Calculate the result and convert to string without scientific notation
        result := (base_num * (10^exp_num))::TEXT;
        RETURN SPLIT_PART(result, '.', 1); -- Return only integer part
    ELSE
        -- If not scientific notation, just replace comma with dot and return as text
        RETURN SPLIT_PART(REPLACE(num_text, ',', '.'), '.', 1);
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- If any error occurs, return NULL
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 5. Convert the data with proper type handling
INSERT INTO rianthis_time_entries_raw
SELECT 
    NULLIF(user_id, '')::BIGINT,
    username,
    NULLIF(time_entry_id, '')::BIGINT,
    description,
    CASE WHEN billable = 'WAHR' THEN true ELSE false END,
    time_labels,
    (convert_scientific(start) * 1000)::BIGINT, -- Convert to milliseconds if needed
    start_text,
    (convert_scientific(stop) * 1000)::BIGINT,  -- Convert to milliseconds if needed
    stop_text,
    NULLIF(time_tracked, '')::BIGINT,
    time_tracked_text,
    NULLIF(space_id, '')::BIGINT,
    space_name,
    NULLIF(folder_id, '')::BIGINT,
    folder_name,
    NULLIF(list_id, '')::BIGINT,
    list_name,
    task_id,
    task_name,
    task_status,
    NULLIF(due_date, '')::BIGINT,
    due_date_text,
    NULLIF(start_date, '')::BIGINT,
    start_date_text,
    NULLIF(task_time_estimated, '')::BIGINT,
    task_time_estimated_text,
    NULLIF(task_time_spent, '')::BIGINT,
    task_time_spent_text,
    NULLIF(user_total_time_estimated, '')::BIGINT,
    user_total_time_estimated_text,
    NULLIF(user_total_time_tracked, '')::BIGINT,
    user_total_time_tracked_text,
    tags,
    checklists,
    NULLIF(user_period_time_spent, '')::BIGINT,
    user_period_time_spent_text,
    (convert_scientific(date_created) * 1000)::BIGINT, -- Convert to milliseconds if needed
    date_created_text,
    custom_task_id,
    parent_task_id,
    NULLIF(progress, '')::INT,
    phase_dep
FROM rianthis_time_entries_raw_text
-- Only include rows with valid data
WHERE user_id ~ '^[0-9]+$';

-- Clean up the helper function
DROP FUNCTION convert_scientific(text);

-- Clean up the temporary table
DROP TABLE rianthis_time_entries_raw_text;

\echo 'Importing rianthis_team_mapping.csv'
\copy rianthis_team_mapping FROM '/import/rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"');

\echo 'Importing Contract_Info.csv'
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
COPY rianthis_team_mapping FROM '/rianthis_team_mapping.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"', ESCAPE '\\');

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

COPY contract_info_raw FROM '/Contract_Info.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true, QUOTE '"', ESCAPE '\\');

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
