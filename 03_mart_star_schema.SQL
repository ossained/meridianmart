
-- 03_mart_star_schema.sql 
-- Builds the star schema (dims + fact) from staging.


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
    SELECT 1 FROM mart.dim_products d
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
    SELECT 1 FROM mart.dim_staff d
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
    SELECT 1 FROM mart.dim_stores d
    WHERE d.store_id = s.store_id
);

-- Manager dimension (masters)
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
    SELECT 1 FROM mart.dim_masters d
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
        SELECT 1 FROM mart.dim_date d
        WHERE d.date_key = t.transaction_timestamp::date
  );


-- FACT TABLE (UPDATED WITH master_id)


CREATE TABLE IF NOT EXISTS mart.fact_transactions (
    transaction_key      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_no           VARCHAR(100),
    sale_timestamp       TIMESTAMP,
    date_key             DATE,
    store_id             VARCHAR(50),
    staff_id             VARCHAR(50),
    product_id           VARCHAR(50),
    master_id            VARCHAR(50),   
    quantity             INTEGER,
    unit_price_ghs       DECIMAL(10,2),
    total_amount_ghs     DECIMAL(10,2),
    payment_method       VARCHAR(50),
    customer_phone       VARCHAR(50)
);

INSERT INTO mart.fact_transactions (
    receipt_no,
    sale_timestamp,
    date_key,
    store_id,
    staff_id,
    product_id,
    master_id,   -- NEW
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
    m.master_id,   
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
LEFT JOIN mart.dim_masters m
    ON t.store_id = m.store_id
WHERE NOT EXISTS (
    SELECT 1
    FROM mart.fact_transactions f
    WHERE f.receipt_no = t.receipt_no
      AND f.product_id IS NOT DISTINCT FROM p.product_id
      AND f.sale_timestamp = t.transaction_timestamp
      AND f.master_id IS NOT DISTINCT FROM m.master_id   
);
