-- Team Mapping Tabelle leeren und neu füllen
TRUNCATE TABLE rianthis_team_mapping;

COPY rianthis_team_mapping(username, role, monatsstunden)
FROM '/team_mapping.csv'
DELIMITER ','
CSV HEADER;

-- Contract Info Tabelle leeren
TRUNCATE TABLE contract_info;

-- Temporäre Tabelle für CSV import
CREATE TEMP TABLE contract_info_raw (
    list_name TEXT,
    customer_type TEXT,
    angebot_h TEXT,
    vertragsbegin_text TEXT,
    vertragsstunden TEXT
);

COPY contract_info_raw
FROM '/contract_info.csv'
DELIMITER ','
CSV HEADER;

-- Einfügen in finale Tabelle mit Umrechnung HH:MM:SS → Dezimalstunden
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
