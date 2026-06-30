CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dim;
CREATE SCHEMA IF NOT EXISTS fact;

DROP SCHEMA RAW CASCADE;
DROP SCHEMA staging CASCADE;
DROP SCHEMA dim CASCADE;
DROP SCHEMA fact CASCADE;




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

 
CREATE TABLE raw.ref_product_manager (
    product_id      TEXT,
    product_name    TEXT,
    category        TEXT,
    unit_price_ghs  TEXT,
    last_updated    TEXT,
    updated_by      TEXT,
    load_timestamp  TEXT
);

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
CREATE TABLE raw.ref_store_manager (
    store_id       TEXT,
    city           TEXT,
    region         TEXT,
    load_timestamp TEXT
);




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
FROM raw.ref_product_master;


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
    NULLIF(staff_id, '') AS staff_id,
    NULLIF(full_name, '') AS full_name,
    NULLIF(role, '') AS role,
    NULLIF(store_id, '') AS store_id,
    NULLIF(store_city, '') AS store_city,
    NULLIF(phone_number, '') AS phone_number,

    CASE
        WHEN date_hired LIKE '%/%/%'
            THEN to_date(date_hired, 'MM/DD/YYYY')
        WHEN date_hired LIKE '%-%-%'
            THEN date_hired::date
        ELSE NULL
    END AS date_hired,

    NULLIF(employment_status, '') AS employment_status,
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.ref_staff_manager;

CREATE TABLE staging.managers_master (
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
SELECT DISTINCT 
    NULLIF(manager_id, '') AS manager_id,
    NULLIF(full_name, '') AS full_name,
    NULLIF(role, '') AS role,
    NULLIF(store_id, '') AS store_id,
    NULLIF(phone_number, '') AS phone_number,
    NULLIF(email, '') AS email,

    CASE
        WHEN date_appointed LIKE '%/%/%'
            THEN to_date(date_appointed, 'MM/DD/YYYY')
        WHEN date_appointed LIKE '%-%-%'
            THEN date_appointed::date
        ELSE NULL
    END AS date_appointed,

    NULLIF(reports_to, '') AS reports_to,
    
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.ref_managers;


CREATE TABLE staging.transactions (
    transaction_timestamp   TIMESTAMP NOT NULL,
    store_id                VARCHAR(50) NOT NULL,
    staff_name              VARCHAR(255) NOT NULL,
    receipt_no              VARCHAR(100) NOT NULL,
    customer_phone          VARCHAR(50),
    product_sold            VARCHAR(255) NOT NULL,
    quantity                INTEGER NOT NULL CHECK (quantity > 0),
    payment_method          VARCHAR(50) NOT NULL CHECK (payment_method IN ('Cash', 'Card', 'Mobile Money')),
    source_file             VARCHAR(255) NOT NULL,
    loaded_timestamp        TIMESTAMP NOT NULL,

    CONSTRAINT fk_transactions_store
        FOREIGN KEY (store_id)
        REFERENCES staging.stores_master (store_id)
);

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

    NULLIF(payment_method, '') AS payment_method,
    source_file,
    CURRENT_TIMESTAMP AS loaded_timestamp
FROM raw.transactions;

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.validation_log (
    log_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    layer            VARCHAR(50),     -- raw, staging, dim, fact
    table_name       VARCHAR(100),    -- which table was checked
    check_name       VARCHAR(100),    -- what was being validated
    records_checked  INTEGER,         -- total rows in the table at time of check
    records_failed   INTEGER,         -- rows that failed the check
    severity         VARCHAR(20),     -- ERROR, WARNING, INFO
    notes            TEXT,            -- human readable explanation
    checked_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Validation: products
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

-- Validation: stores
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

-- Validation: staff
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

-- Validation: managers
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

-- Validation: transactions
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

-- Validation: dim.products
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'dim', 'dim.products', 'row_count_vs_staging',
    (SELECT COUNT(*) FROM staging.products_master),
    ABS(COUNT(*) - (SELECT COUNT(*) FROM staging.products_master)),
    'WARNING', 'Row count mismatch between staging and dim.products'
FROM dim.products;

-- Validation: dim.staff
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'dim', 'dim.staff', 'null_store_id',
    COUNT(*), COUNT(*) FILTER (WHERE store_id IS NULL),
    'ERROR', 'Staff in dim with no store assigned'
FROM dim.staff;

-- Validation: dim.stores
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'dim', 'dim.stores', 'null_region',
    COUNT(*), COUNT(*) FILTER (WHERE region IS NULL),
    'WARNING', 'Stores in dim with no region'
FROM dim.stores;

-- Validation: dim.masters
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'dim', 'dim.masters', 'null_email',
    COUNT(*), COUNT(*) FILTER (WHERE email IS NULL),
    'INFO', 'Managers with no email on record'
FROM dim.masters;

-- Validation: fact.transactions
INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'fact', 'fact.transactions', 'unmatched_staff',
    COUNT(*), COUNT(*) FILTER (WHERE staff_id IS NULL),
    'WARNING', 'Transactions where staff_name had no match in dim.staff'
FROM fact.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'fact', 'fact.transactions', 'unmatched_product',
    COUNT(*), COUNT(*) FILTER (WHERE product_id IS NULL),
    'WARNING', 'Transactions where product_sold had no match in dim.products'
FROM fact.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'fact', 'fact.transactions', 'null_total_amount',
    COUNT(*), COUNT(*) FILTER (WHERE total_amount_ghs IS NULL),
    'ERROR', 'Transactions with no total amount (likely missing product match)'
FROM fact.transactions;

INSERT INTO audit.validation_log (layer, table_name, check_name, records_checked, records_failed, severity, notes)
SELECT 'fact', 'fact.transactions', 'zero_or_negative_total',
    COUNT(*), COUNT(*) FILTER (WHERE total_amount_ghs <= 0),
    'ERROR', 'Transactions with zero or negative total amount'
FROM fact.transactions;


-- View all failures
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



CREATE TABLE IF NOT EXISTS dim.products (
    product_id      VARCHAR(50) PRIMARY KEY,
    product_name    VARCHAR(255),
    category        VARCHAR(100),
    unit_price_ghs  DECIMAL(10,2),
    last_updated    TIMESTAMP,
    updated_by      VARCHAR(255)
);

INSERT INTO dim.products (
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
    FROM dim.products d
    WHERE d.product_id = s.product_id
);

CREATE TABLE IF NOT EXISTS dim.staff (
    staff_id          VARCHAR(50) PRIMARY KEY,
    full_name         VARCHAR(255),
    role              VARCHAR(100),
    store_id          VARCHAR(50),
    store_city        VARCHAR(100),
    phone_number      VARCHAR(50),
    date_hired        DATE,
    employment_status VARCHAR(50)
);

INSERT INTO dim.staff (
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
    FROM dim.staff d
    WHERE d.staff_id = s.staff_id
);

CREATE TABLE IF NOT EXISTS dim.stores (
    store_id VARCHAR(50) PRIMARY KEY,
    city     VARCHAR(255),
    region   VARCHAR(100)
);

INSERT INTO dim.stores (
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
    FROM dim.stores d
    WHERE d.store_id = s.store_id
);

CREATE TABLE IF NOT EXISTS dim.masters (
    master_id      VARCHAR(50) PRIMARY KEY,
    full_name      VARCHAR(255),
    role           VARCHAR(100),
    store_id       VARCHAR(50),
    phone_number   VARCHAR(50),
    email          VARCHAR(255),
    date_appointed DATE,
    reports_to     VARCHAR(50)
);

INSERT INTO dim.masters (
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
    FROM dim.masters d
    WHERE d.master_id = s.manager_id
);

CREATE TABLE IF NOT EXISTS dim.date (
    date_key        DATE PRIMARY KEY,
    year            INT,
    month           INT,
    day             INT,
    weekday_name    VARCHAR(20),
    weekday_number  INT
);

INSERT INTO dim.date (
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
        FROM dim.date d
        WHERE d.date_key = t.transaction_timestamp::date
  );

CREATE TABLE IF NOT EXISTS fact.transactions (
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

INSERT INTO fact.transactions (
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
LEFT JOIN dim.staff s
    ON LOWER(t.staff_name) = LOWER(s.full_name)
LEFT JOIN dim.products p
    ON LOWER(t.product_sold) = LOWER(p.product_name)
WHERE NOT EXISTS (
    SELECT 1
    FROM fact.transactions f
    WHERE f.receipt_no = t.receipt_no
      AND f.product_id = p.product_id
      AND f.sale_timestamp = t.transaction_timestamp
);
