
-- 01_schema_raw.sql
-- Creates all schemas + raw landing tables.
-- Run ONCE during initial setup.


-- SCHEMA CREATION
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- RAW LAYER: Unprocessed landing data

-- Transaction data
CREATE TABLE IF NOT EXISTS raw.transactions (
    timestamp                        TEXT,
    store_id                         TEXT,
    staff_name                       TEXT,
    receipt_no                       TEXT,
    customer_phone_number_optional   TEXT,
    product_sold                     TEXT,
    quantity                         TEXT,
    payment_method                   TEXT,
    source_file                      TEXT,   -- store_01.csv, store_02.csv, etc.
    load_timestamp                   TEXT    -- when pipeline loaded it
);

-- Reference: Store managers
CREATE TABLE IF NOT EXISTS raw.ref_managers (
    manager_id        TEXT,
    full_name         TEXT,
    role              TEXT,
    store_id          TEXT,
    phone_number      TEXT,
    email             TEXT,
    date_appointed    TEXT,
    reports_to        TEXT,
    load_timestamp    TEXT
);

-- Reference: Product catalog
CREATE TABLE IF NOT EXISTS raw.ref_product_manager (
    product_id      TEXT,
    product_name    TEXT,
    category        TEXT,
    unit_price_ghs  TEXT,
    last_updated    TEXT,
    updated_by      TEXT,
    load_timestamp  TEXT
);

-- Reference: Staff information
CREATE TABLE IF NOT EXISTS raw.ref_staff_manager (
    staff_id          TEXT,
    full_name         TEXT,
    role              TEXT,
    store_id          TEXT,
    store_city        TEXT,
    phone_number      TEXT,
    date_hired        TEXT,
    employment_status TEXT,
    load_timestamp    TEXT
);

-- Reference: Store locations
CREATE TABLE IF NOT EXISTS raw.ref_store_manager (
    store_id       TEXT,
    city           TEXT,
    region         TEXT,
    load_timestamp TEXT
);