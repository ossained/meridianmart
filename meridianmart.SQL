-- SCHEMA CREATION
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS audit;

-- RAW LAYER: Unprocessed landing data

-- Transaction data 
CREATE TABLE raw.transactions (
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
CREATE TABLE raw.ref_managers (
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
CREATE TABLE raw.ref_product_manager (
    product_id      TEXT,
    product_name    TEXT,
    category        TEXT,
    unit_price_ghs  TEXT,
    last_updated    TEXT,
    updated_by      TEXT,
    load_timestamp  TEXT
);

-- Reference: Staff information
CREATE TABLE raw.ref_staff_manager (
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
CREATE TABLE raw.ref_store_manager (
    store_id       TEXT,
    city           TEXT,
    region         TEXT,
    load_timestamp TEXT
);

-- STAGING LAYER: Cleaned and typed master data

-- Master product catalog
CREATE TABLE staging.products_master (
    product_id      VARCHAR(50)  NOT NULL,
    product_name    VARCHAR(255) NOT NULL,
    category        VARCHAR(100) NOT NULL,
    unit_price_ghs  DECIMAL(10,2) NOT NULL CHECK (unit_price_ghs >= 0),
    last_updated    TIMESTAMP,
    updated_by      VARCHAR(255),
    load_timestamp  TIMESTAMP NOT NULL,

    CONSTRAINT pk_products_master PRIMARY KEY (product_id)
);

INSERT INTO staging.products_master (
    product_id,
    product_name,
    category,
    unit_price_ghs,
    last_updated,
    updated_by,
    load_timestamp
)
SELECT DISTINCT
    NULLIF(product_id, '') AS product_id,
    NULLIF(product_name, '') AS product_name,
    NULLIF(category, '') AS category,
    NULLIF(unit_price_ghs, '')::DECIMAL(10,2) AS unit_price_ghs,
    CURRENT_DATE AS last_updated,
    updated_by,
    CURRENT_TIMESTAMP AS load_timestamp
FROM raw.ref_product_manager;

-- Master store locations
CREATE TABLE staging.stores_master (
    store_id         VARCHAR(50)  NOT NULL,
    city             VARCHAR(255) NOT NULL,
    region           VARCHAR(100) NOT NULL,
    loaded_timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_stores_master PRIMARY KEY (store_id)
);

INSERT INTO staging.stores_master (
    store_id,
    city,
    region,
    loaded_timestamp
)
SELECT DISTINCT
    NULLIF(store_id, '') AS store_id,
    NULLIF(city, '') AS city,
    NULLIF(region, '') AS region,
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.ref_store_manager;

-- Master staff 
CREATE TABLE staging.staff_master (
    staff_id          VARCHAR(50)  NOT NULL,
    full_name         VARCHAR(255) NOT NULL,
    role              VARCHAR(100) NOT NULL,
    store_id          VARCHAR(50)  NOT NULL,
    store_city        VARCHAR(100),
    phone_number      VARCHAR(50),
    date_hired        DATE,
    employment_status VARCHAR(50) CHECK (employment_status IN ('Active', 'Inactive', 'Suspended')),
    loaded_timestamp  TIMESTAMP NOT NULL,

    CONSTRAINT pk_staff_master PRIMARY KEY (staff_id),
    CONSTRAINT fk_staff_master_store
        FOREIGN KEY (store_id)
        REFERENCES staging.stores_master (store_id)
);

-- Load staff 
WITH city_map AS (
    SELECT DISTINCT
        city,
        store_id
    FROM staging.stores_master
)
INSERT INTO staging.staff_master (
    staff_id,
    full_name,
    role,
    store_id,
    store_city,
    phone_number,
    date_hired,
    employment_status,
    loaded_timestamp
)
SELECT DISTINCT
    NULLIF(s.staff_id, '') AS staff_id,
    NULLIF(s.full_name, '') AS full_name,
    NULLIF(s.role, '') AS role,
    NULLIF(s.store_city, '') AS store_city,
    NULLIF(s.phone_number, '') AS phone_number,
    CASE
        WHEN s.date_hired LIKE '%/%/%'
            THEN to_date(s.date_hired, 'MM/DD/YYYY')
        WHEN s.date_hired LIKE '%-%-%'
            THEN s.date_hired::date
        ELSE NULL
    END AS date_hired,
    NULLIF(s.employment_status, '') AS employment_status,
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.ref_staff_manager s
LEFT JOIN city_map cm
    ON s.store_city = cm.city;

-- Master managers 
CREATE TABLE IF NOT EXISTS staging.managers_master (
    manager_id        VARCHAR(50)  NOT NULL,
    full_name         VARCHAR(255) NOT NULL,
    role              VARCHAR(100) NOT NULL,
    store_id          VARCHAR(50)  NOT NULL,
    phone_number      VARCHAR(50),
    email             VARCHAR(255),
    date_appointed    DATE,
    reports_to        VARCHAR(50),
    loaded_timestamp  TIMESTAMP NOT NULL,

    CONSTRAINT pk_managers_master PRIMARY KEY (manager_id),
    CONSTRAINT fk_managers_master_store
        FOREIGN KEY (store_id)
        REFERENCES staging.stores_master (store_id)
);

-- Load managers 
WITH raw_clean AS (
    SELECT DISTINCT ON (manager_id)
        manager_id,
        full_name,
        role,
        phone_number,
        email,
        date_appointed,
        reports_to,
        store_id AS raw_store_id
    FROM raw.ref_managers
    ORDER BY manager_id
),
extracted_codes AS (
    SELECT
        manager_id,
        full_name,
        role,
        phone_number,
        email,
        date_appointed,
        reports_to,
        raw_store_id,
        CASE
            WHEN LOWER(email) ~ 's[0-9]{3}'
                THEN LOWER(regexp_replace(email, '.*s([0-9]{3}).*', '\1'))
            ELSE NULL
        END AS store_code
    FROM raw_clean
),
store_code_map AS (
    SELECT
        store_id,
        LOWER(regexp_replace(store_id, '.*([0-9]{3}).*', '\1')) AS store_code
    FROM staging.stores_master
),
region_map AS (
    SELECT
        region,
        store_id
    FROM staging.stores_master
),
final_rows AS (
    SELECT DISTINCT ON (e.manager_id)
        e.manager_id,
        e.full_name,
        e.role,
        COALESCE(scm.store_id, rm.store_id) AS store_id,
        e.phone_number,
        e.email,
        CASE
            WHEN e.date_appointed LIKE '%/%/%'
                THEN to_date(e.date_appointed, 'MM/DD/YYYY')
            WHEN e.date_appointed LIKE '%-%-%'
                THEN e.date_appointed::date
            ELSE NULL
        END AS date_appointed,
        e.reports_to,
        CURRENT_TIMESTAMP AS loaded_timestamp
    FROM extracted_codes e
    LEFT JOIN store_code_map scm
        ON e.store_code = scm.store_code
    LEFT JOIN region_map rm
        ON e.raw_store_id = rm.region
    ORDER BY e.manager_id
)
INSERT INTO staging.managers_master (
    manager_id,
    full_name,
    role,
    store_id,
    phone_number,
    email,
    date_appointed,
    reports_to,
    loaded_timestamp
)
SELECT
    manager_id,
    full_name,
    role,
    store_id,
    phone_number,
    email,
    date_appointed,
    reports_to,
    loaded_timestamp
FROM final_rows
ON CONFLICT (manager_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    store_id = EXCLUDED.store_id,
    phone_number = EXCLUDED.phone_number,
    email = EXCLUDED.email,
    date_appointed = EXCLUDED.date_appointed,
    reports_to = EXCLUDED.reports_to,
    loaded_timestamp = EXCLUDED.loaded_timestamp;

-- Staging transactions 
CREATE TABLE IF NOT EXISTS staging.transactions (
    transaction_timestamp   TIMESTAMP NOT NULL,
    store_id                VARCHAR(50) NOT NULL,
    staff_name              VARCHAR(255) NOT NULL,
    receipt_no              VARCHAR(100) NOT NULL,
    customer_phone          VARCHAR(50),
    product_sold            VARCHAR(255) NOT NULL,
    quantity                INTEGER NOT NULL CHECK (quantity > 0),
    payment_method          VARCHAR(50) NOT NULL CHECK (
        payment_method IN ('Cash', 'Card', 'Mobile Money')
    ),
    source_file             VARCHAR(255) NOT NULL,
    loaded_timestamp        TIMESTAMP NOT NULL,

    CONSTRAINT fk_transactions_store
        FOREIGN KEY (store_id)
        REFERENCES staging.stores_master (store_id)
);

-- Load transactions with timestamp parsing and payment standardization
INSERT INTO staging.transactions (
    transaction_timestamp,
    store_id,
    staff_name,
    receipt_no,
    customer_phone,
    product_sold,
    quantity,
    payment_method,
    source_file,
    loaded_timestamp
)
SELECT DISTINCT
    CASE
        WHEN timestamp LIKE '%/%/%'
            THEN to_timestamp(timestamp, 'MM/DD/YYYY HH24:MI:SS')
        WHEN timestamp LIKE '%-%-%'
            THEN timestamp::timestamp
        ELSE NULL
    END AS transaction_timestamp,
    NULLIF(store_id, '') AS store_id,
    NULLIF(staff_name, '') AS staff_name,
    NULLIF(receipt_no, '') AS receipt_no,
    NULLIF(customer_phone_number_optional, '') AS customer_phone,
    NULLIF(product_sold, '') AS product_sold,
    CASE
        WHEN quantity ~ '^[0-9]+$' THEN quantity::integer
        ELSE NULL
    END AS quantity,
    CASE
        WHEN LOWER(payment_method) IN ('cash') THEN 'Cash'
        WHEN LOWER(payment_method) IN ('card') THEN 'Card'
        WHEN LOWER(payment_method) IN ('mobile money', 'momo', 'mo mo', 'mobile_money') THEN 'Mobile Money'
        WHEN LOWER(payment_method) = 'transfer' THEN 'Mobile Money'
    END AS payment_method,
    source_file,
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.transactions;

-- AUDIT LAYER: Data quality validation

-- Central validation log
CREATE TABLE IF NOT EXISTS audit.validation_log (
    log_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    layer            VARCHAR(50),
    table_name       VARCHAR(100),
    check_name       VARCHAR(100),
    records_checked  INTEGER,
    records_failed   INTEGER,
    severity         VARCHAR(20),     -- ERROR, WARNING, INFO
    notes            TEXT,
    checked_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- STAGING VALIDATION CHECKS

-- Products validation
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.products_master', 'null_product_id',
    COUNT(*), COUNT(*) FILTER (WHERE product_id IS NULL),
    'ERROR', 'Products with no product_id after load'
FROM staging.products_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.products_master', 'null_product_name',
    COUNT(*), COUNT(*) FILTER (WHERE product_name IS NULL),
    'ERROR', 'Products with no product_name after load'
FROM staging.products_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.products_master', 'negative_unit_price',
    COUNT(*), COUNT(*) FILTER (WHERE unit_price_ghs < 0),
    'ERROR', 'Products with a negative price'
FROM staging.products_master;

-- Stores validation
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.stores_master', 'null_store_id',
    COUNT(*), COUNT(*) FILTER (WHERE store_id IS NULL),
    'ERROR', 'Stores with no store_id after load'
FROM staging.stores_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.stores_master', 'null_city',
    COUNT(*), COUNT(*) FILTER (WHERE city IS NULL),
    'WARNING', 'Stores with no city'
FROM staging.stores_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.stores_master', 'null_region',
    COUNT(*), COUNT(*) FILTER (WHERE region IS NULL),
    'WARNING', 'Stores with no region'
FROM staging.stores_master;

-- Staff validation
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.staff_master', 'null_staff_id',
    COUNT(*), COUNT(*) FILTER (WHERE staff_id IS NULL),
    'ERROR', 'Staff rows with no staff_id'
FROM staging.staff_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.staff_master', 'null_date_hired',
    COUNT(*), COUNT(*) FILTER (WHERE date_hired IS NULL),
    'WARNING', 'Staff rows where date_hired could not be parsed'
FROM staging.staff_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.staff_master', 'invalid_employment_status',
    COUNT(*), COUNT(*) FILTER (WHERE employment_status NOT IN ('Active', 'Inactive', 'Suspended')),
    'ERROR', 'Staff with employment_status outside allowed values'
FROM staging.staff_master;

-- Managers validation
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.managers_master', 'null_manager_id',
    COUNT(*), COUNT(*) FILTER (WHERE manager_id IS NULL),
    'ERROR', 'Managers with no manager_id'
FROM staging.managers_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.managers_master', 'null_store_id',
    COUNT(*), COUNT(*) FILTER (WHERE store_id IS NULL),
    'ERROR', 'Managers with no store assigned'
FROM staging.managers_master;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.managers_master', 'null_date_appointed',
    COUNT(*), COUNT(*) FILTER (WHERE date_appointed IS NULL),
    'WARNING', 'Managers where date_appointed could not be parsed'
FROM staging.managers_master;

-- Transactions validation
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.transactions', 'null_transaction_timestamp',
    COUNT(*), COUNT(*) FILTER (WHERE transaction_timestamp IS NULL),
    'ERROR', 'Rows where timestamp could not be parsed from raw'
FROM staging.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.transactions', 'null_receipt_no',
    COUNT(*), COUNT(*) FILTER (WHERE receipt_no IS NULL),
    'ERROR', 'Transactions with no receipt number'
FROM staging.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.transactions', 'null_quantity',
    COUNT(*), COUNT(*) FILTER (WHERE quantity IS NULL),
    'ERROR', 'Rows where quantity could not be cast to integer'
FROM staging.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.transactions', 'invalid_payment_method',
    COUNT(*), COUNT(*) FILTER (WHERE payment_method NOT IN ('Cash', 'Card', 'Mobile Money')),
    'ERROR', 'Payment method outside allowed values'
FROM staging.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'staging', 'staging.transactions', 'missing_customer_phone',
    COUNT(*), COUNT(*) FILTER (WHERE customer_phone IS NULL),
    'INFO', 'Transactions with no customer phone (optional field)'
FROM staging.transactions;

-- MART LAYER: Analytics-ready dimensional model

-- Product dimension
CREATE TABLE IF NOT EXISTS mart.dim_products (
    product_id      VARCHAR(50) PRIMARY KEY,
    product_name    VARCHAR(255),
    category        VARCHAR(100),
    unit_price_ghs  DECIMAL(10,2),
    last_updated    TIMESTAMP,
    updated_by      VARCHAR(255)
);

INSERT INTO mart.dim_products (
    product_id,
    product_name,
    category,
    unit_price_ghs,
    last_updated,
    updated_by
)
SELECT
    s.product_id,
    s.product_name,
    s.category,
    s.unit_price_ghs,
    s.last_updated,
    s.updated_by
FROM staging.products_master s
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.dim_products d
    WHERE d.product_id = s.product_id
);

-- Staff dimension
CREATE TABLE IF NOT EXISTS mart.dim_staff (
    staff_id          VARCHAR(50) PRIMARY KEY,
    full_name         VARCHAR(255),
    role              VARCHAR(100),
    store_id          VARCHAR(50),
    store_city        VARCHAR(100),
    phone_number      VARCHAR(50),
    date_hired        DATE,
    employment_status VARCHAR(50)
);

INSERT INTO mart.dim_staff (
    staff_id,
    full_name,
    role,
    store_id,
    store_city,
    phone_number,
    date_hired,
    employment_status
)
SELECT
    s.staff_id,
    s.full_name,
    s.role,
    s.store_id,
    s.store_city,
    s.phone_number,
    s.date_hired,
    s.employment_status
FROM staging.staff_master s
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.dim_staff d
    WHERE d.staff_id = s.staff_id
);

-- Store dimension
CREATE TABLE IF NOT EXISTS mart.dim_stores (
    store_id VARCHAR(50) PRIMARY KEY,
    city     VARCHAR(255),
    region   VARCHAR(100)
);

INSERT INTO mart.dim_stores (
    store_id,
    city,
    region
)
SELECT
    s.store_id,
    s.city,
    s.region
FROM staging.stores_master s
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.dim_stores d
    WHERE d.store_id = s.store_id
);

-- Manager dimension
CREATE TABLE IF NOT EXISTS mart.dim_masters (
    master_id      VARCHAR(50) PRIMARY KEY,
    full_name      VARCHAR(255),
    role           VARCHAR(100),
    store_id       VARCHAR(50),
    phone_number   VARCHAR(50),
    email          VARCHAR(255),
    date_appointed DATE,
    reports_to     VARCHAR(50)
);

INSERT INTO mart.dim_masters (
    master_id,
    full_name,
    role,
    store_id,
    phone_number,
    email,
    date_appointed,
    reports_to
)
SELECT
    s.manager_id AS master_id,
    s.full_name,
    s.role,
    s.store_id,
    s.phone_number,
    s.email,
    s.date_appointed,
    s.reports_to
FROM staging.managers_master s
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.dim_masters d
    WHERE d.master_id = s.manager_id
);

-- Date dimension
CREATE TABLE IF NOT EXISTS mart.dim_date (
    date_key        DATE PRIMARY KEY,
    year            INT,
    month           INT,
    day             INT,
    weekday_name    VARCHAR(20),
    weekday_number  INT
);

INSERT INTO mart.dim_date (
    date_key,
    year,
    month,
    day,
    weekday_name,
    weekday_number
)
SELECT DISTINCT
    t.transaction_timestamp::date AS date_key,
    EXTRACT(YEAR FROM t.transaction_timestamp),
    EXTRACT(MONTH FROM t.transaction_timestamp),
    EXTRACT(DAY FROM t.transaction_timestamp),
    TO_CHAR(t.transaction_timestamp, 'Day'),
    EXTRACT(ISODOW FROM t.transaction_timestamp)
FROM staging.transactions t
WHERE t.transaction_timestamp IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM mart.dim_date d
        WHERE d.date_key = t.transaction_timestamp::date
  );

-- Fact transactions with calculated amounts
CREATE TABLE IF NOT EXISTS mart.fact_transactions (
    transaction_key      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_no           VARCHAR(100),
    sale_timestamp       TIMESTAMP,
    date_key             DATE,
    store_id             VARCHAR(50),
    staff_id             VARCHAR(50),
    product_id           VARCHAR(50),
    quantity             INTEGER,
    unit_price_ghs       DECIMAL(10,2),
    total_amount_ghs     DECIMAL(10,2),
    payment_method       VARCHAR(50),
    customer_phone       VARCHAR(50)
);

-- Load fact table 
INSERT INTO mart.fact_transactions (
    receipt_no,
    sale_timestamp,
    date_key,
    store_id,
    staff_id,
    product_id,
    quantity,
    unit_price_ghs,
    total_amount_ghs,
    payment_method,
    customer_phone
)
SELECT
    t.receipt_no,
    t.transaction_timestamp AS sale_timestamp,
    t.transaction_timestamp::date AS date_key,
    t.store_id,
    s.staff_id,
    p.product_id,
    t.quantity,
    p.unit_price_ghs,
    t.quantity * p.unit_price_ghs AS total_amount_ghs,
    t.payment_method,
    t.customer_phone
FROM staging.transactions t
LEFT JOIN mart.dim_staff s
    ON LOWER(t.staff_name) = LOWER(s.full_name)
LEFT JOIN mart.dim_products p
    ON LOWER(t.product_sold) = LOWER(p.product_name)
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.fact_transactions f
    WHERE f.receipt_no = t.receipt_no
      AND f.product_id IS NOT DISTINCT FROM p.product_id
      AND f.sale_timestamp = t.transaction_timestamp
);

-- MART VALIDATION CHECKS

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.dim_products', 'row_count_vs_staging',
    (SELECT COUNT(*) FROM staging.products_master),
    ABS(COUNT(*) - (SELECT COUNT(*) FROM staging.products_master)),
    'WARNING', 'Row count mismatch between staging and mart.dim_products'
FROM mart.dim_products;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.dim_staff', 'null_store_id',
    COUNT(*), COUNT(*) FILTER (WHERE store_id IS NULL),
    'ERROR', 'Staff in mart with no store assigned'
FROM mart.dim_staff;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.dim_stores', 'null_region',
    COUNT(*), COUNT(*) FILTER (WHERE region IS NULL),
    'WARNING', 'Stores in mart with no region'
FROM mart.dim_stores;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.dim_masters', 'null_email',
    COUNT(*), COUNT(*) FILTER (WHERE email IS NULL),
    'INFO', 'Managers with no email on record'
FROM mart.dim_masters;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.fact_transactions', 'unmatched_staff',
    COUNT(*), COUNT(*) FILTER (WHERE staff_id IS NULL),
    'WARNING', 'Transactions where staff_name had no match in mart.dim_staff'
FROM mart.fact_transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.fact_transactions', 'unmatched_product',
    COUNT(*), COUNT(*) FILTER (WHERE product_id IS NULL),
    'WARNING', 'Transactions where product_sold had no match in mart.dim_products'
FROM mart.fact_transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.fact_transactions', 'null_total_amount',
    COUNT(*), COUNT(*) FILTER (WHERE total_amount_ghs IS NULL),
    'ERROR', 'Transactions with no total amount (likely missing product match)'
FROM mart.fact_transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'mart', 'mart.fact_transactions', 'zero_or_negative_total',
    COUNT(*), COUNT(*) FILTER (WHERE total_amount_ghs <= 0),
    'ERROR', 'Transactions with zero or negative total amount'
FROM mart.fact_transactions;

-- Validation report: View all failures
SELECT
    layer,
    table_name,
    check_name,
    records_checked,
    records_failed,
    severity,
    notes,
    checked_at
FROM audit.validation_log
WHERE records_failed > 0
ORDER BY
    CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
    checked_at;