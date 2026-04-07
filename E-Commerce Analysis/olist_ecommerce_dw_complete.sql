-- ============================================================
-- OLIST BRAZILIAN E-COMMERCE — DATA WAREHOUSE
-- Full SQL Pipeline: Staging → Clean → Star Schema
-- 
-- Author      : Mahesh
-- Database    : ecommerce_dw (MS SQL Server)
-- Dataset     : Olist Brazilian E-Commerce (Kaggle)
-- Stages      : 1. Staging Tables (stg_)
--               2. Clean Tables (clean_)
--               3. Star Schema (dim_ + fact_)
--               4. dim_date Fix (continuous date range)
--               5. Data Quality (remove incomplete months)
--               6. Validation Queries
-- ============================================================


-- ============================================================
-- STAGE 1: STAGING TABLES
-- All columns as NVARCHAR — raw data as-is from CSV files
-- Loaded via BULK INSERT or SSMS Import Data Wizard
-- ============================================================

-- NOTE: Staging tables were loaded directly via SSMS Import
-- Data Wizard due to embedded line breaks and encoding issues
-- in some CSV files (particularly stg_order_reviews).
-- stg_sellers is excluded — not used in this analysis.

-- Tables created in this stage:
--   stg_customers, stg_orders, stg_order_items,
--   stg_order_payments, stg_order_reviews, stg_products,
--   stg_geolocation, stg_category_translation


-- ============================================================
-- STAGE 2: CLEAN TABLES
-- Applies: quote removal, capitalisation, label standardisation,
--          column renames, category translation join
-- Data types remain NVARCHAR — casting deferred to star schema
-- ============================================================

-- 2.1 clean_customers
DROP TABLE IF EXISTS clean_customers;

SELECT
    REPLACE(customer_id,              '"', '') AS customer_id,
    REPLACE(customer_unique_id,       '"', '') AS customer_unique_id,
    REPLACE(customer_zip_code_prefix, '"', '') AS customer_zip_code_prefix,
    UPPER(LEFT(TRIM(customer_city), 1))
        + LOWER(SUBSTRING(TRIM(customer_city), 2, LEN(customer_city))) AS customer_city,
    UPPER(TRIM(customer_state))                                         AS customer_state
INTO clean_customers
FROM stg_customers;


-- 2.2 clean_orders
DROP TABLE IF EXISTS clean_orders;

SELECT
    REPLACE(order_id,    '"', '') AS order_id,
    REPLACE(customer_id, '"', '') AS customer_id,
    UPPER(LEFT(TRIM(order_status), 1))
        + LOWER(SUBSTRING(TRIM(order_status), 2, LEN(order_status))) AS order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
INTO clean_orders
FROM stg_orders;


-- 2.3 clean_order_items
DROP TABLE IF EXISTS clean_order_items;

SELECT
    REPLACE(order_id,      '"', '') AS order_id,
    REPLACE(order_item_id, '"', '') AS order_item_id,
    REPLACE(product_id,    '"', '') AS product_id,
    REPLACE(seller_id,     '"', '') AS seller_id,
    shipping_limit_date,
    price,
    freight_value
INTO clean_order_items
FROM stg_order_items;


-- 2.4 clean_order_payments
DROP TABLE IF EXISTS clean_order_payments;

SELECT
    REPLACE(order_id, '"', '') AS order_id,
    payment_sequential,
    CASE TRIM(payment_type)
        WHEN 'credit_card' THEN 'Credit card'
        WHEN 'debit_card'  THEN 'Debit card'
        WHEN 'boleto'      THEN 'Boleto'
        WHEN 'voucher'     THEN 'Voucher'
        ELSE TRIM(payment_type)
    END                        AS payment_type,
    payment_installments,
    payment_value
INTO clean_order_payments
FROM stg_order_payments;


-- 2.5 clean_products
-- Joins clean_category_translation for English category name
-- Renames product_name_lenght → product_name_length (typo fix)
DROP TABLE IF EXISTS clean_products;

SELECT
    REPLACE(p.product_id,             '"', '') AS product_id,
    REPLACE(p.product_category_name,  '"', '') AS product_category_name,
    ct.product_category_name_english,
    p.product_name_lenght        AS product_name_length,
    p.product_description_lenght AS product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
INTO clean_products
FROM stg_products p
LEFT JOIN clean_category_translation ct
    ON REPLACE(TRIM(p.product_category_name), '"', '')
       = TRIM(ct.product_category_name);


-- Already-clean tables (no transformations needed):
--   clean_category_translation  — kept as-is
--   clean_geolocation           — kept as-is
--   clean_reviews               — kept as-is


-- ============================================================
-- STAGE 3: STAR SCHEMA
-- Dimensions and Facts with proper data type casting
-- All monetary/numeric measures: DECIMAL(10,2)
-- All IDs: NVARCHAR
-- All dates: DATE or DATETIME
--
-- Schema:
--   dim_customers    → fact_orders (customer_id)
--   dim_date         → fact_orders (purchase_date → date_id)
--   dim_geolocation  → dim_customers (zip_code)
--   dim_products     → fact_order_items (product_id)
--   fact_orders      → fact_order_payments (order_id)
--   fact_orders      → fact_order_items (order_id)
--   fact_orders      → fact_reviews (order_id)
-- ============================================================

-- 3.1 dim_customers
DROP TABLE IF EXISTS dim_customers;

SELECT
    CAST(customer_id              AS NVARCHAR(50))  AS customer_id,
    CAST(customer_unique_id       AS NVARCHAR(50))  AS customer_unique_id,
    CAST(customer_zip_code_prefix AS NVARCHAR(10))  AS customer_zip_code_prefix,
    CAST(customer_city            AS NVARCHAR(100)) AS customer_city,
    CAST(customer_state           AS NVARCHAR(10))  AS customer_state
INTO dim_customers
FROM clean_customers;


-- 3.2 dim_geolocation
-- Deduplicated by zip_code using AVG lat/lng
DROP TABLE IF EXISTS dim_geolocation;

SELECT
    CAST(zip_code        AS NVARCHAR(10))  AS zip_code,
    CAST(AVG(latitude)   AS DECIMAL(10,6)) AS latitude,
    CAST(AVG(longitude)  AS DECIMAL(10,6)) AS longitude,
    CAST(MAX(city)       AS NVARCHAR(100)) AS city,
    CAST(MAX(state)      AS NVARCHAR(10))  AS state
INTO dim_geolocation
FROM clean_geolocation
GROUP BY zip_code;


-- 3.3 dim_products
DROP TABLE IF EXISTS dim_products;

SELECT
    CAST(product_id                    AS NVARCHAR(50))  AS product_id,
    CAST(product_category_name         AS NVARCHAR(100)) AS product_category_name,
    CAST(product_category_name_english AS NVARCHAR(100)) AS product_category_name_english,
    CAST(product_name_length           AS INT)           AS product_name_length,
    CAST(product_description_length    AS INT)           AS product_description_length,
    CAST(product_photos_qty            AS INT)           AS product_photos_qty,
    CAST(product_weight_g              AS DECIMAL(10,2)) AS product_weight_g,
    CAST(product_length_cm             AS DECIMAL(10,2)) AS product_length_cm,
    CAST(product_height_cm             AS DECIMAL(10,2)) AS product_height_cm,
    CAST(product_width_cm              AS DECIMAL(10,2)) AS product_width_cm
INTO dim_products
FROM clean_products;


-- 3.4 dim_date
-- Initial version — built from order dates only
-- NOTE: Replaced in Stage 4 with continuous date range
DROP TABLE IF EXISTS dim_date;

DECLARE @start_date DATE = (SELECT CAST(MIN(order_purchase_timestamp) AS DATE) FROM clean_orders);
DECLARE @end_date   DATE = (SELECT CAST(MAX(order_estimated_delivery_date) AS DATE) FROM clean_orders);

WITH date_sequence AS (
    SELECT @start_date AS date_value
    UNION ALL
    SELECT DATEADD(DAY, 1, date_value)
    FROM date_sequence
    WHERE date_value < @end_date
)
SELECT
    CAST(date_value                          AS DATE)         AS date_id,
    CAST(date_value                          AS DATE)         AS full_date,
    CAST(DAY(date_value)                     AS INT)          AS day,
    CAST(MONTH(date_value)                   AS INT)          AS month,
    CAST(DATENAME(MONTH, date_value)         AS NVARCHAR(20)) AS month_name,
    CAST(YEAR(date_value)                    AS INT)          AS year,
    CAST(DATEPART(QUARTER, date_value)       AS INT)          AS quarter,
    CAST(DATENAME(WEEKDAY, date_value)       AS NVARCHAR(20)) AS day_of_week,
    CAST(DATEPART(WEEKDAY, date_value)       AS INT)          AS day_of_week_number
INTO dim_date
FROM date_sequence
OPTION (MAXRECURSION 3000);


-- 3.5 fact_orders
-- Grain: one row per order
-- Timestamps kept for Power BI DAX calculations
DROP TABLE IF EXISTS fact_orders;

SELECT
    CAST(order_id                          AS NVARCHAR(50)) AS order_id,
    CAST(customer_id                       AS NVARCHAR(50)) AS customer_id,
    CAST(order_status                      AS NVARCHAR(50)) AS order_status,
    CAST(order_purchase_timestamp          AS DATE)         AS purchase_date,
    CAST(order_approved_at                 AS DATE)         AS approved_date,
    CAST(order_delivered_carrier_date      AS DATE)         AS delivered_carrier_date,
    CAST(order_delivered_customer_date     AS DATE)         AS delivered_customer_date,
    CAST(order_estimated_delivery_date     AS DATE)         AS estimated_delivery_date,
    CAST(order_purchase_timestamp          AS DATETIME)     AS order_purchase_timestamp,
    CAST(order_approved_at                 AS DATETIME)     AS order_approved_at,
    CAST(order_delivered_carrier_date      AS DATETIME)     AS order_delivered_carrier_date,
    CAST(order_delivered_customer_date     AS DATETIME)     AS order_delivered_customer_date,
    CAST(order_estimated_delivery_date     AS DATETIME)     AS order_estimated_delivery_date
INTO fact_orders
FROM clean_orders;


-- 3.6 fact_order_payments
-- Grain: one row per payment record
-- PK: order_id + payment_sequential
DROP TABLE IF EXISTS fact_order_payments;

SELECT
    CAST(order_id                               AS NVARCHAR(50))  AS order_id,
    CAST(CAST(payment_sequential AS INT)        AS INT)           AS payment_sequential,
    CAST(payment_type                           AS NVARCHAR(50))  AS payment_type,
    CAST(CAST(payment_installments AS INT)      AS INT)           AS payment_installments,
    CAST(CAST(payment_value AS DECIMAL(10,2))   AS DECIMAL(10,2)) AS payment_value
INTO fact_order_payments
FROM clean_order_payments;


-- 3.7 fact_order_items
-- Grain: one row per order line item
-- PK: order_id + order_item_id
DROP TABLE IF EXISTS fact_order_items;

SELECT
    CAST(order_id                                                             AS NVARCHAR(50))  AS order_id,
    CAST(order_item_id                                                        AS INT)           AS order_item_id,
    CAST(product_id                                                           AS NVARCHAR(50))  AS product_id,
    CAST(seller_id                                                            AS NVARCHAR(50))  AS seller_id,
    CAST(shipping_limit_date                                                  AS DATE)          AS shipping_limit_date,
    CAST(CAST(price         AS DECIMAL(10,2))                                 AS DECIMAL(10,2)) AS price,
    CAST(CAST(freight_value AS DECIMAL(10,2))                                 AS DECIMAL(10,2)) AS freight_value,
    CAST(CAST(price AS DECIMAL(10,2)) + CAST(freight_value AS DECIMAL(10,2)) AS DECIMAL(10,2)) AS total_item_value
INTO fact_order_items
FROM clean_order_items;


-- 3.8 fact_reviews
-- Grain: one row per review_id + order_id
-- Deduplicated via ROW_NUMBER() — review_id alone is not unique
-- in the Olist dataset (known data quality issue)
DROP TABLE IF EXISTS fact_reviews;

WITH deduped_reviews AS (
    SELECT
        review_id,
        order_id,
        review_score,
        review_comment_message,
        review_creation_date,
        ROW_NUMBER() OVER (
            PARTITION BY review_id, order_id
            ORDER BY review_creation_date DESC
        ) AS rn
    FROM clean_reviews
)
SELECT
    CAST(review_id              AS NVARCHAR(50))  AS review_id,
    CAST(order_id               AS NVARCHAR(50))  AS order_id,
    CAST(CAST(review_score AS INT) AS INT)        AS review_score,
    CAST(review_comment_message AS NVARCHAR(MAX)) AS review_comment_message,
    CAST(review_creation_date   AS DATE)          AS review_creation_date
INTO fact_reviews
FROM deduped_reviews
WHERE rn = 1;


-- ============================================================
-- STAGE 4: dim_date FIX — Add year_month columns
-- Required for Power BI time intelligence and correct
-- X-axis sorting on trend charts
-- Run AFTER star schema is created
-- ============================================================

ALTER TABLE dim_date
ADD year_month NVARCHAR(10);
GO

UPDATE dim_date
SET year_month =
    LEFT(DATENAME(MONTH, full_date), 3) + ' ' + CAST(YEAR(full_date) AS NVARCHAR(4));
GO

ALTER TABLE dim_date
ADD year_month_sort INT;
GO

UPDATE dim_date
SET year_month_sort = (year * 100) + month;
GO

-- Power BI instruction:
-- After refresh, go to Data view → dim_date table →
-- click year_month column → Column tools →
-- Sort by Column → year_month_sort


-- ============================================================
-- STAGE 5: DATA QUALITY — Remove incomplete months
-- Sep & Oct 2018 had significantly fewer orders (incomplete
-- data collection period) — removed to avoid misleading trends
-- ============================================================

-- Verify before deleting
SELECT
    YEAR(order_purchase_timestamp)  AS yr,
    MONTH(order_purchase_timestamp) AS mth,
    COUNT(*)                        AS order_count
FROM fact_orders
WHERE order_purchase_timestamp >= '2018-09-01'
GROUP BY
    YEAR(order_purchase_timestamp),
    MONTH(order_purchase_timestamp)
ORDER BY yr, mth;

-- Remove incomplete months from all fact tables
DELETE FROM fact_orders
WHERE order_purchase_timestamp >= '2018-09-01';

DELETE FROM fact_order_items
WHERE order_id NOT IN (SELECT order_id FROM fact_orders);

DELETE FROM fact_order_payments
WHERE order_id NOT IN (SELECT order_id FROM fact_orders);

DELETE FROM fact_reviews
WHERE order_id NOT IN (SELECT order_id FROM fact_orders);


-- ============================================================
-- STAGE 6: VALIDATION QUERIES
-- Run after each stage to confirm data integrity
-- Expected: 0 rows for all duplicate and orphan checks
-- ============================================================

-- 6.1 Duplicate checks on primary keys
SELECT 'clean_customers'    AS tbl, customer_id   AS key_val, COUNT(*) AS cnt FROM clean_customers    GROUP BY customer_id              HAVING COUNT(*) > 1
UNION ALL
SELECT 'clean_orders',               order_id,                 COUNT(*) FROM clean_orders             GROUP BY order_id                 HAVING COUNT(*) > 1
UNION ALL
SELECT 'clean_products',             product_id,               COUNT(*) FROM clean_products           GROUP BY product_id               HAVING COUNT(*) > 1;

-- Composite PK checks
SELECT 'clean_order_payments' AS tbl, order_id, COUNT(*) AS cnt
FROM clean_order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

SELECT 'clean_order_items' AS tbl, order_id, COUNT(*) AS cnt
FROM clean_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Reviews deduplication check (review_id + order_id)
SELECT 'clean_reviews' AS tbl, review_id, order_id, COUNT(*) AS cnt
FROM clean_reviews
GROUP BY review_id, order_id
HAVING COUNT(*) > 1;


-- 6.2 NULL checks on key columns
SELECT 'fact_orders - NULL order_id'    AS issue, COUNT(*) AS cnt FROM fact_orders    WHERE order_id    IS NULL
UNION ALL
SELECT 'fact_orders - NULL customer_id',           COUNT(*) FROM fact_orders    WHERE customer_id IS NULL
UNION ALL
SELECT 'fact_order_payments - NULL order_id',      COUNT(*) FROM fact_order_payments WHERE order_id IS NULL
UNION ALL
SELECT 'fact_order_items - NULL order_id',         COUNT(*) FROM fact_order_items    WHERE order_id IS NULL
UNION ALL
SELECT 'fact_order_items - NULL product_id',       COUNT(*) FROM fact_order_items    WHERE product_id IS NULL
UNION ALL
SELECT 'fact_reviews - NULL review_id',            COUNT(*) FROM fact_reviews        WHERE review_id IS NULL
UNION ALL
SELECT 'dim_customers - NULL customer_id',         COUNT(*) FROM dim_customers       WHERE customer_id IS NULL
UNION ALL
SELECT 'dim_products - NULL product_id',           COUNT(*) FROM dim_products        WHERE product_id IS NULL;


-- 6.3 FK integrity checks (orphan records)
SELECT 'fact_orders → dim_customers'       AS fk_check, COUNT(*) AS orphans FROM fact_orders o        WHERE NOT EXISTS (SELECT 1 FROM dim_customers  c WHERE c.customer_id = o.customer_id)
UNION ALL
SELECT 'fact_order_payments → fact_orders',           COUNT(*) FROM fact_order_payments p WHERE NOT EXISTS (SELECT 1 FROM fact_orders     o WHERE o.order_id   = p.order_id)
UNION ALL
SELECT 'fact_order_items → fact_orders',              COUNT(*) FROM fact_order_items    i WHERE NOT EXISTS (SELECT 1 FROM fact_orders     o WHERE o.order_id   = i.order_id)
UNION ALL
SELECT 'fact_order_items → dim_products',             COUNT(*) FROM fact_order_items    i WHERE NOT EXISTS (SELECT 1 FROM dim_products    p WHERE p.product_id = i.product_id)
UNION ALL
SELECT 'fact_reviews → fact_orders',                  COUNT(*) FROM fact_reviews        r WHERE NOT EXISTS (SELECT 1 FROM fact_orders     o WHERE o.order_id   = r.order_id);


-- 6.4 Row count summary
SELECT 'dim_customers'        AS table_name, COUNT(*) AS row_count FROM dim_customers
UNION ALL SELECT 'dim_geolocation',          COUNT(*) FROM dim_geolocation
UNION ALL SELECT 'dim_products',             COUNT(*) FROM dim_products
UNION ALL SELECT 'dim_date',                 COUNT(*) FROM dim_date
UNION ALL SELECT 'fact_orders',              COUNT(*) FROM fact_orders
UNION ALL SELECT 'fact_order_payments',      COUNT(*) FROM fact_order_payments
UNION ALL SELECT 'fact_order_items',         COUNT(*) FROM fact_order_items
UNION ALL SELECT 'fact_reviews',             COUNT(*) FROM fact_reviews;
