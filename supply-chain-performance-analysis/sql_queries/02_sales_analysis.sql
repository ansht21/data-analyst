-- =========================================================================
-- Project: Supply Chain Inventory Optimization & Performance Analysis
-- Script: 02_Sales_Analysis.sql
-- Description: Analyzes key business metrics, including data quality,
--              sales channel revenue, trends, warehousing efficiency,
--              and detailed profit margins.
--
-- Each section states the BUSINESS QUESTION it answers, the metric used, and
-- the answer obtained from the 7,991-order dataset (2018-2020). Findings are
-- cross-referenced to the Q-numbers in this project's README.
-- =========================================================================

USE SupplyChainDB;

-- -------------------------------------------------------------------------
-- 1. BUSINESS QUESTION: Can we trust this data before reporting on it?
-- Metric: null counts across the four date columns driving every lead-time KPI
-- Answer: 7,991 records, zero nulls in any date column -- lead-time metrics
--         are computed on the full population, not a filtered subset.
-- -------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_records,
    SUM(CASE WHEN ProcuredDate IS NULL THEN 1 ELSE 0 END) AS procured_date_nulls,
    SUM(CASE WHEN OrderDate IS NULL THEN 1 ELSE 0 END) AS order_date_nulls,
    SUM(CASE WHEN ShipDate IS NULL THEN 1 ELSE 0 END) AS ship_date_nulls,
    SUM(CASE WHEN DeliveryDate IS NULL THEN 1 ELSE 0 END) AS delivery_date_nulls
FROM SupplyChainSales;


-- -------------------------------------------------------------------------
-- 2. BUSINESS QUESTION: Which sales channel is most profitable, and is any
--    channel discounting its way into weak margins?
-- Metric: orders, gross/net revenue, avg discount, profit and margin by channel
-- Answer: In-Store is the largest channel ($34.0M revenue, 3,298 orders) but
--         Wholesale has the BEST margin at 38.13% on the smallest volume
--         ($9.2M). Margins are tightly clustered 36.94%-38.13% -- no channel
--         is discounting itself into trouble.
-- Action: Channel mix is healthy; growth should target Wholesale, which keeps
--         the most of every dollar sold. (README Q2)
-- -------------------------------------------------------------------------
SELECT
    SalesChannel,
    COUNT(OrderNumber) AS total_orders,
    SUM(OrderQuantity) AS total_units_sold,

    -- Gross Revenue before discounts
    ROUND(SUM(OrderQuantity * UnitPrice), 2) AS gross_revenue_usd,

    -- Average Discount applied to orders
    ROUND(AVG(DiscountApplied) * 100, 2) AS avg_discount_percentage,

    -- Net Revenue after discount
    ROUND(SUM(OrderQuantity * UnitPrice * (1 - DiscountApplied)), 2) AS net_revenue_usd,

    -- Total Cost
    ROUND(SUM(OrderQuantity * UnitCost), 2) AS total_cost_usd,

    -- Net Profit
    ROUND(SUM(OrderQuantity * UnitPrice * (1 - DiscountApplied)) - SUM(OrderQuantity * UnitCost), 2) AS net_profit_usd,

    -- Profit Margin (%)
    ROUND(
        (SUM(OrderQuantity * UnitPrice * (1 - DiscountApplied)) - SUM(OrderQuantity * UnitCost)) /
        SUM(OrderQuantity * UnitPrice * (1 - DiscountApplied)) * 100,
        2
    ) AS profit_margin_percentage
FROM SupplyChainSales
GROUP BY SalesChannel
ORDER BY net_revenue_usd DESC;


-- -------------------------------------------------------------------------
-- 3. BUSINESS QUESTION: Is the business growing, and is there a seasonal
--    pattern we should plan inventory around?
-- Metric: monthly order count and net revenue across 2018-2020
-- Answer: Revenue grew from $19.3M (2018, partial year from May) to $31.5M
--         (2019) and $31.9M (2020) -- growth flattened between 2019 and 2020
--         (+1.0%). No strong seasonal cycle; monthly revenue sits in a
--         $2.2M-$3.1M band throughout.
-- Action: Plan flat inventory rather than seasonal build-ups. (Q3)
-- -------------------------------------------------------------------------
SELECT
    YEAR(OrderDate) AS order_year,
    MONTH(OrderDate) AS order_month,
    COUNT(OrderNumber) AS monthly_order_count,
    ROUND(SUM(OrderQuantity * UnitPrice * (1 - DiscountApplied)), 2) AS net_revenue_usd
FROM SupplyChainSales
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY order_year ASC, order_month ASC;


-- -------------------------------------------------------------------------
-- 4. BUSINESS QUESTION: Which warehouse is slowest, so we know where to
--    invest in fulfilment capacity?
-- Metric: avg order-to-ship, ship-to-delivery, and total fulfilment days
-- Answer: Barely any difference. Average delivery ranges only 5.35 to 5.59
--         days across all six warehouses -- a 0.24-day spread.
-- Action: Do NOT invest per-warehouse on this evidence. Section 6 tests this
--         properly and shows why the warehouse is the wrong thing to blame. (Q4)
-- -------------------------------------------------------------------------
SELECT
    WarehouseCode,
    COUNT(OrderNumber) AS total_orders_fulfilled,
    ROUND(AVG(DATEDIFF(ShipDate, OrderDate)), 2) AS avg_days_order_to_ship,
    ROUND(AVG(DATEDIFF(DeliveryDate, ShipDate)), 2) AS avg_days_ship_to_delivery,
    ROUND(AVG(DATEDIFF(DeliveryDate, OrderDate)), 2) AS avg_total_fulfillment_days
FROM SupplyChainSales
GROUP BY WarehouseCode
ORDER BY avg_total_fulfillment_days ASC;


-- -------------------------------------------------------------------------
-- 5. BUSINESS QUESTION: Are we losing money on any orders through aggressive
--    discounting?
-- Metric: order-level net revenue vs cost, flagged profitable/unprofitable
-- Answer: NO -- zero unprofitable orders across all 7,991. Even the worst SKU
--         holds a 34.44% margin, and orders discounted 20%+ still return
--         38.28%. Discounting is well controlled against cost.
-- Action: Pricing floors are working. This is a clean bill of health, and it
--         is worth stating explicitly rather than leaving unexamined. (Q5)
-- -------------------------------------------------------------------------
SELECT
    OrderNumber,
    ProductID,
    OrderQuantity,
    UnitPrice,
    DiscountApplied,
    ROUND((OrderQuantity * UnitPrice * (1 - DiscountApplied)), 2) AS order_net_revenue_usd,
    ROUND((OrderQuantity * UnitCost), 2) AS order_cost_usd,
    ROUND((OrderQuantity * UnitPrice * (1 - DiscountApplied)) - (OrderQuantity * UnitCost), 2) AS order_profit_usd,
    CASE
        WHEN (UnitPrice * (1 - DiscountApplied)) < UnitCost THEN 'UNPROFITABLE'
        ELSE 'PROFITABLE'
    END AS profitability_status
FROM SupplyChainSales
ORDER BY order_profit_usd ASC
LIMIT 10;


-- =========================================================================
-- ADVANCED ANALYSIS
-- Sections 6-8 use CTEs and window functions (STDDEV, LAG, NTILE) to answer
-- the question the project was set up to solve: WHY are half our orders late?
-- =========================================================================


-- -------------------------------------------------------------------------
-- 6. BUSINESS QUESTION: Half of all orders arrive late. Is that a specific
--    warehouse's fault, or is it systemic across the whole network?
-- Metric: on-time rate, avg and STDDEV of delivery days, share of all late
--         orders, and revenue exposed -- per warehouse
-- Technique: STDDEV + coefficient of variation + window share of total
-- Answer: SYSTEMIC, not warehouse-specific. On-time rate spans just
--         48.85%-53.69% and the standard deviation of delivery days is
--         2.82-2.88 days at EVERY warehouse -- essentially identical spread.
--         The network-wide on-time rate is 50.53%, and $41.0M (49.6% of all
--         revenue) sits on late orders.
--         NMK1003 looks like the worst offender at 31.9% of all late orders,
--         but that is only because it handles 31.4% of all orders. Its rate
--         (49.70%) is average. Ranking by COUNT would blame the wrong site.
-- Action: Do not open a per-warehouse improvement project. Every site is
--         equally inconsistent, which points at the ordering/scheduling
--         process upstream, not at any one facility's execution. (README Q6)
-- -------------------------------------------------------------------------
WITH warehouse_stats AS (
    SELECT
        WarehouseCode,
        COUNT(OrderNumber)                                   AS total_orders,
        SUM(CASE WHEN DeliveryDays <= 5 THEN 1 ELSE 0 END)   AS on_time_orders,
        SUM(CASE WHEN DeliveryDays >  5 THEN 1 ELSE 0 END)   AS late_orders,
        AVG(DeliveryDays)                                    AS avg_delivery_days,
        STDDEV_SAMP(DeliveryDays)                            AS sd_delivery_days,
        AVG(ProcureToOrderDays)                              AS avg_procure_days,
        SUM(CASE WHEN DeliveryDays > 5 THEN Revenue ELSE 0 END) AS revenue_on_late_orders
    FROM SupplyChainSales
    GROUP BY WarehouseCode
)
SELECT
    WarehouseCode,
    total_orders,
    ROUND(on_time_orders * 100.0 / total_orders, 2) AS on_time_rate_pct,
    ROUND(avg_delivery_days, 2)                     AS avg_delivery_days,
    ROUND(sd_delivery_days, 2)                      AS sd_delivery_days,
    -- coefficient of variation: spread relative to the mean, comparable across sites
    ROUND(sd_delivery_days / avg_delivery_days, 3)  AS delivery_variability_cv,
    ROUND(avg_procure_days, 2)                      AS avg_procure_days,
    -- what share of ALL late orders does this site account for?
    ROUND(late_orders * 100.0 / SUM(late_orders) OVER (), 2) AS pct_of_all_late_orders,
    -- ...versus what share of all orders it handles. If these match, the site
    -- is simply big, not bad.
    ROUND(total_orders * 100.0 / SUM(total_orders) OVER (), 2) AS pct_of_all_orders,
    ROUND(revenue_on_late_orders, 2)                AS revenue_at_risk_usd,
    RANK() OVER (ORDER BY on_time_orders * 1.0 / total_orders DESC) AS reliability_rank
FROM warehouse_stats
ORDER BY on_time_rate_pct DESC;


-- -------------------------------------------------------------------------
-- 7. BUSINESS QUESTION: Is our profit margin eroding over time, and which
--    months broke trend badly enough to investigate?
-- Metric: monthly margin with month-over-month change, via LAG()
-- Technique: LAG() over an ordered monthly aggregate
-- Answer: Margin is stable, not eroding -- it oscillates around 37% for all
--         32 months (2018-05 to 2020-12) with no downward drift. The worst
--         single month is 2020-10 at 35.44%, a ~2pp drop, which recovers
--         to 37.14% the following month.
-- Action: No margin-erosion problem exists. Treat 2020-10 as a one-off to
--         explain, not a trend to correct. (Q7)
-- -------------------------------------------------------------------------
WITH monthly_margin AS (
    SELECT
        YEAR(OrderDate)  AS order_year,
        MONTH(OrderDate) AS order_month,
        COUNT(OrderNumber) AS orders,
        SUM(Revenue)     AS revenue,
        SUM(Profit)      AS profit,
        SUM(Profit) / SUM(Revenue) * 100 AS margin_pct
    FROM SupplyChainSales
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
)
SELECT
    order_year,
    order_month,
    orders,
    ROUND(revenue, 2)    AS revenue_usd,
    ROUND(margin_pct, 2) AS margin_pct,
    ROUND(LAG(margin_pct) OVER (ORDER BY order_year, order_month), 2) AS prev_month_margin_pct,
    ROUND(margin_pct - LAG(margin_pct) OVER (ORDER BY order_year, order_month), 2)
        AS margin_change_pp,
    CASE
        WHEN margin_pct - LAG(margin_pct) OVER (ORDER BY order_year, order_month) < -1.5
            THEN 'INVESTIGATE: sharp drop'
        WHEN margin_pct - LAG(margin_pct) OVER (ORDER BY order_year, order_month) >  1.5
            THEN 'Improvement'
        ELSE 'Within normal range'
    END AS trend_flag
FROM monthly_margin
ORDER BY order_year, order_month;


-- -------------------------------------------------------------------------
-- 8. BUSINESS QUESTION: Does heavier discounting actually cost us margin?
--    Should we cap discounts?
-- Metric: order volume, revenue, realised margin and late-rate by discount band
-- Technique: CASE WHEN banding + window share of total
-- Answer: NO -- margin does not fall as discounts rise. Orders discounted 20%+
--         realise a 38.28% margin, HIGHER than the 5-10% band's 37.07%.
--         Discounts are evidently applied to already-high-margin products.
-- Action: A blanket discount cap would destroy revenue without protecting
--         margin. The pricing team's current discretion is working. (Q8)
-- -------------------------------------------------------------------------
SELECT
    CASE
        WHEN DiscountApplied <= 0.05 THEN 'A: 0-5%'
        WHEN DiscountApplied <= 0.10 THEN 'B: 5-10%'
        WHEN DiscountApplied <= 0.20 THEN 'C: 10-20%'
        ELSE                              'D: 20%+'
    END AS discount_band,
    COUNT(OrderNumber)                          AS total_orders,
    ROUND(SUM(Revenue), 2)                      AS revenue_usd,
    ROUND(SUM(Profit), 2)                       AS profit_usd,
    ROUND(SUM(Profit) / SUM(Revenue) * 100, 2)  AS realised_margin_pct,
    ROUND(COUNT(OrderNumber) * 100.0 / SUM(COUNT(OrderNumber)) OVER (), 2) AS pct_of_orders,
    ROUND(SUM(Revenue) * 100.0 / SUM(SUM(Revenue)) OVER (), 2)             AS pct_of_revenue
FROM SupplyChainSales
GROUP BY discount_band
ORDER BY discount_band;
