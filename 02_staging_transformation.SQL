-- =========================================================
-- 02_staging_transform.sql
-- Builds staging tables (typed + constrained) and loads
-- them from the raw layer. Runs daily, after extraction.

-- TABLE DEFINITIONS (created once, no-op on later runs)
-- ---------------------------------------------------------

-- Master product catalog
CREATE TABLE IF NOT EXISTS staging.products_master (
    product_id      VARCHAR(50)  NOT NULL,
    product_name    VARCHAR(255) NOT NULL,
    category        VARCHAR(100) NOT NULL,
    unit_price_ghs  DECIMAL(10,2) NOT NULL CHECK (unit_price_ghs >= 0),
    last_updated    TIMESTAMP,
    updated_by      VARCHAR(255),
    load_timestamp  TIMESTAMP NOT NULL,

    CONSTRAINT pk_products_master PRIMARY KEY (product_id)
);

-- Master store locations
CREATE TABLE IF NOT EXISTS staging.stores_master (
    store_id         VARCHAR(50)  NOT NULL,
    city             VARCHAR(255) NOT NULL,
    region           VARCHAR(100) NOT NULL,
    loaded_timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_stores_master PRIMARY KEY (store_id)
);

-- Master staff
CREATE TABLE IF NOT EXISTS staging.staff_master (
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

-- IDEMPOTENT REFRESH: clear all staging tables in one go
-- (CASCADE handles the FK dependency order automatically)

TRUNCATE TABLE
    staging.products_master,
    staging.stores_master,
    staging.staff_master,
    staging.managers_master,
    staging.transactions
RESTART IDENTITY CASCADE;

-- LOADS

-- Load products
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

-- Load stores
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