-- =========================================================================
-- Project: Supply Chain Inventory Optimization & Performance Analysis
-- Script: 01_Database_Setup.sql
-- Description: Creates the database schema and handles the bulk import of
--              raw supply chain transaction data.
-- =========================================================================

-- 1. Create and initialize the database
CREATE DATABASE IF NOT EXISTS SupplyChainDB;
USE SupplyChainDB;

-- 2. Drop the table if it already exists to ensure a clean setup
DROP TABLE IF EXISTS SupplyChainSales;

-- IMPORTANT: This script loads the CLEANED pipeline output
--   data/Cleaned_Supplychain_Data.csv  (produced by src/data_cleaning.py)
-- The cleaning step already standardizes headers, strips '$'/',' from currency
-- columns, and writes ISO (YYYY-MM-DD) dates -- so the load below works directly.
-- (Loading the RAW csv would fail: it has '$1,001.18' currency strings and
--  day-first dates like '31/5/18'. Always run src/data_cleaning.py first.)

-- 3. Create the transactions table schema with appropriate data types
CREATE TABLE SupplyChainSales (
    OrderNumber VARCHAR(20) NOT NULL,
    SalesChannel VARCHAR(50),
    WarehouseCode VARCHAR(20),
    ProcuredDate DATE,
    OrderDate DATE,
    ShipDate DATE,
    DeliveryDate DATE,
    CurrencyCode VARCHAR(10),
    SalesTeamID INT,
    CustomerID INT,
    StoreID INT,
    ProductID INT,
    OrderQuantity INT,
    DiscountApplied DECIMAL(5,4), -- Stores discount values (e.g., 0.0500 for 5%)
    UnitCost DECIMAL(10,2),       -- Cost per unit in USD
    UnitPrice DECIMAL(10,2),      -- Selling price per unit in USD
    DeliveryDays INT,
    OrderToShipDays INT,
    ProcureToOrderDays INT,
    Revenue DECIMAL(14,2),
    TotalCost DECIMAL(14,2),
    Profit DECIMAL(14,2),
    PRIMARY KEY (OrderNumber)
);

-- Note: MySQL require checking local_infile variables or secure_file_priv paths
-- to load local dataset files into the database.
-- SHOW VARIABLES LIKE 'secure_file_priv';

-- 4. Bulk Import Transaction Data
-- Replace the path below with the location of Cleaned_Supplychain_Data.csv.
-- The trailing engineered columns (profit_margin, on_time, order_year,
-- order_month) are skipped via throwaway @vars.
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/Cleaned_Supplychain_Data.csv'
INTO TABLE SupplyChainSales
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    OrderNumber,
    SalesChannel,
    WarehouseCode,
    ProcuredDate,
    OrderDate,
    ShipDate,
    DeliveryDate,
    CurrencyCode,
    SalesTeamID,
    CustomerID,
    StoreID,
    ProductID,
    OrderQuantity,
    DiscountApplied,
    UnitCost,
    UnitPrice,
    DeliveryDays,
    OrderToShipDays,
    ProcureToOrderDays,
    Revenue,
    TotalCost,
    Profit,
    @profit_margin,
    @on_time,
    @order_year,
    @order_month
);

-- 5. Data Validation Check
-- Expect 7,991 rows. If this returns fewer, the LOAD DATA step silently
-- skipped malformed rows and every downstream KPI will be understated.
SELECT COUNT(*) AS total_rows_imported FROM SupplyChainSales;
