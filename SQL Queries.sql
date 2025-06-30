use ecommerce;
-- 1. Overall return metrics
SELECT 
    COUNT(*) as total_orders,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate,
    SUM(GrossSales) as total_gross_sales,
    SUM(ReturnValue) as total_return_value,
    ROUND(SUM(ReturnValue) / SUM(GrossSales) * 100, 2) as revenue_lost_pct
FROM df_ecommerce;

-- 2. Return rate by category with profitability impact
SELECT 
    category,
    COUNT(*) as orders,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate,
    SUM(GrossSales) as return_value,
    SUM(ReturnProcessingCost + ReturnLogisticsCost) as return_costs,
    SUM(NetSales) as net_revenue
FROM df_ecommerce
GROUP BY category
ORDER BY return_rate DESC;

-- 3. Customer segmentation analysis
WITH order_level_summary AS (
    SELECT
        OrderID,
        CustomerID, -- Keep CustomerID to join later
        SUM(GrossSales) AS total_order_value -- Sum line-item values to get total for each order
    FROM
        df_ecommerce
    GROUP BY
        OrderID, CustomerID -- Group by both to ensure correct association
),
customer_metrics AS (
    SELECT
        ols.CustomerID,
        COUNT(DISTINCT ols.OrderID) AS total_orders, -- Count distinct orders for each customer
        SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
		ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate,
        SUM(ols.total_order_value) AS total_spent, -- Total spent by customer (sum of their order totals)
        -- Now, correctly calculate Average Order Value (AOV) per customer
        AVG(ols.total_order_value) AS avg_order_value_per_customer
    FROM
        order_level_summary ols
    JOIN
        df_ecommerce e ON ols.OrderID = e.OrderID AND ols.CustomerID = e.CustomerID -- Join back to df_ecommerce for Returned_Orders
    GROUP BY
        ols.CustomerID
)
SELECT
    CASE
        WHEN return_rate = 0 THEN 'No Returns'
        WHEN return_rate <= 0.2 THEN 'Low Return'
        WHEN return_rate <= 0.4 THEN 'Medium Return'
        ELSE 'High Return'
    END AS return_segment,
    COUNT(*) AS customers,
    AVG(total_orders) AS avg_orders_per_customer_in_segment, -- Average orders of customers in this segment
    AVG(total_spent) AS avg_clv_in_segment, -- Average total spent (CLV) of customers in this segment
    AVG(avg_order_value_per_customer) AS avg_aov_in_segment -- Average of each customer's AOV in this segment
FROM
    customer_metrics
GROUP BY 1
ORDER BY avg_aov_in_segment DESC;

-- 4. Predictive features for high-return orders
SELECT 
    FirstTimeBuyer,
    UsedSizeGuide,
    MarketingChannel,
    Device,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate
FROM df_ecommerce
GROUP BY 1,2,3,4
HAVING COUNT(*) > 50
ORDER BY return_rate DESC;

-- 5 Returns by customer age group
SELECT 
    CASE 
        WHEN AgeGroup < 25 THEN '18-24'
        WHEN AgeGroup < 35 THEN '25-34' 
        WHEN AgeGroup < 45 THEN '35-44'
        WHEN AgeGroup < 55 THEN '45-54'
        WHEN AgeGroup < 65 THEN '55-64'
        ELSE '65+'
    END as age_group,
    COUNT(*) as total_orders,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate
FROM df_ecommerce
GROUP BY age_group
ORDER BY return_rate DESC;

-- 6 Analyze return behavior by customer tenure
WITH customer_first_order AS (
    SELECT
        CustomerID,
        -- Convert OrderDate to a proper date type here using STR_TO_DATE
        MIN(STR_TO_DATE(OrderDate, '%d-%m-%Y')) AS first_order_date
    FROM
        df_ecommerce
    GROUP BY
        CustomerID
),
customer_analysis AS (
    SELECT
        e.CustomerID,
        DATEDIFF(STR_TO_DATE(e.OrderDate, '%d-%m-%Y'), c.first_order_date) AS days_since_first_order,
        CASE
            WHEN DATEDIFF(STR_TO_DATE(e.OrderDate, '%d-%m-%Y'), c.first_order_date) <= 30 THEN 'New (0-30 days)'
            WHEN DATEDIFF(STR_TO_DATE(e.OrderDate, '%d-%m-%Y'), c.first_order_date) <= 90 THEN 'Regular (31-90 days)'
            ELSE 'Loyal (90+ days)'
        END AS customer_segment,
        e.Returned_Orders
    FROM
        df_ecommerce e
    JOIN
        customer_first_order c ON e.CustomerID = c.CustomerID
)
SELECT
    customer_segment,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate
FROM
    customer_analysis
GROUP BY
    customer_segment
ORDER BY
    return_rate DESC;
    
-- 7 Return trends by month
SELECT 
    EXTRACT(YEAR FROM STR_TO_DATE(OrderDate, '%d-%m-%Y')) as year,
    EXTRACT(MONTH FROM STR_TO_DATE(OrderDate, '%d-%m-%Y')) as month,
    COUNT(*) as total_orders,
    SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) as total_returns,
    ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as return_rate
FROM df_ecommerce
GROUP BY EXTRACT(YEAR FROM STR_TO_DATE(OrderDate, '%d-%m-%Y')),
		 EXTRACT(MONTH FROM STR_TO_DATE(OrderDate, '%d-%m-%Y'))
ORDER BY year, month;

-- 8 Customer lifetime value and return behavior
WITH HighCLVCustomers AS (
    SELECT
        CustomerID,
        ROUND(MAX(CLV), 2) AS customer_lifetime_value_calculated
    FROM
        df_ecommerce
    GROUP BY CustomerID
    HAVING customer_lifetime_value_calculated > 500
),
CustomerReturnSummary AS ( 
    SELECT
        CustomerID,
        SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) AS total_returns,
        ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS return_rate
    FROM
        df_ecommerce
    GROUP BY CustomerID
)
SELECT
    e. CustomerID, 
    hcc.customer_lifetime_value_calculated AS customers_total_clv_value, -- Customer's overall CLV
    crs.total_returns, -- Customer's overall total returns
    crs.return_rate -- Customer's overall return rate
FROM
    df_ecommerce e
JOIN
    HighCLVCustomers hcc ON e.CustomerID = hcc.CustomerID
JOIN
    CustomerReturnSummary crs ON e.CustomerID = crs.CustomerID 
ORDER BY
    e.CustomerID, e.OrderDate; 
    
-- 9 Product Performance: Ranking with RANK() and DENSE_RANK()
WITH CategoryPerformance AS (
    SELECT
        category,
        COUNT(*) AS total_orders,
        SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) AS total_returns,
        ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS return_rate,
        SUM(GrossSales) AS total_gross_sales,
        SUM(ReturnValue) AS total_return_value,
        SUM(ReturnProcessingCost + ReturnLogisticsCost) AS total_return_costs,
        ROUND(SUM(NetSales),2) AS total_net_sales
    FROM
        df_ecommerce
    GROUP BY category
)
SELECT
    category,
    total_orders,
    total_returns,
    return_rate,
    total_net_sales,
    -- Rank by return rate (highest return rate = rank 1)
    RANK() OVER (ORDER BY return_rate DESC) AS return_rate_rank,
    DENSE_RANK() OVER (ORDER BY return_rate DESC) AS return_rate_dense_rank,
    -- Rank by total net sales (highest net sales = rank 1)
    RANK() OVER (ORDER BY total_net_sales DESC) AS net_sales_rank,
    DENSE_RANK() OVER (ORDER BY total_net_sales DESC) AS net_sales_dense_rank
FROM
    CategoryPerformance
ORDER BY
    return_rate_rank, net_sales_rank;
    
-- 10. Customer Lifetime Value (CLV): Cohort Analysis with Window Functions
WITH CustomerAcquisition AS (
    -- Step 1: Identify the first order date (acquisition date) and acquisition cohort for each customer
    SELECT
        CustomerID,
        STR_TO_DATE(MIN(OrderDate), '%d-%m-%Y') AS first_order_date,
        DATE_FORMAT(STR_TO_DATE(MIN(OrderDate), '%d-%m-%Y'), '%Y-%m-01') AS acquisition_cohort -- Format to YYYY-MM-01 for monthly cohort
    FROM
        df_ecommerce
    GROUP BY CustomerID
),
MonthlyCustomerSales AS (
    -- Step 2: Calculate each customer's total sales per month
    SELECT
        e.CustomerID,
        DATE_FORMAT(STR_TO_DATE(e.OrderDate, '%d-%m-%Y'), '%Y-%m-01') AS order_month, -- Month of the current order
        SUM(e.GrossSales) AS monthly_sales
    FROM
        df_ecommerce e
    GROUP BY
        e.CustomerID, DATE_FORMAT(STR_TO_DATE(e.OrderDate, '%d-%m-%Y'), '%Y-%m-01')
),
CumulativeCustomerSales AS (
    -- Step 3: Calculate the cumulative CLV for each customer over time using a Window Function
    SELECT
        mcs.CustomerID,
        ca.acquisition_cohort,
        mcs.order_month,
        -- Window function: Sum monthly_sales for each customer, ordered by month
        SUM(mcs.monthly_sales) OVER (PARTITION BY mcs.CustomerID ORDER BY mcs.order_month) AS cumulative_clv_per_customer,
        -- Calculate the number of months since the customer's acquisition
        TIMESTAMPDIFF(MONTH, ca.first_order_date, mcs.order_month) AS months_since_acquisition
    FROM
        MonthlyCustomerSales mcs
    JOIN
        CustomerAcquisition ca ON mcs.CustomerID = ca.CustomerID
)
SELECT
    acquisition_cohort,
    months_since_acquisition,
    COUNT(DISTINCT CustomerID) AS total_customers_in_cohort, -- Number of unique customers in this cohort
    ROUND(AVG(cumulative_clv_per_customer), 2) AS average_cumulative_clv -- Average cumulative CLV for the cohort
FROM
    CumulativeCustomerSales
GROUP BY
    acquisition_cohort,
    months_since_acquisition
ORDER BY
    acquisition_cohort,
    months_since_acquisition;
    
WITH CustomerOverallMetrics AS (
    SELECT
        CustomerID,
        COUNT(*) AS total_line_items, -- Total line items purchased by the customer
        SUM(CASE WHEN Returned_Orders = 1 THEN 1 ELSE 0 END) AS total_returns,
        ROUND(AVG(CASE WHEN Returned_Orders = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS return_rate,
        SUM(GrossSales) AS total_gross_sales, -- Total sales for AOV calculation
        ROUND(MAX(CLV), 2) AS customer_lifetime_value -- Using the pre-calculated CLV column
    FROM
        df_ecommerce
    GROUP BY CustomerID
),
CustomerFirstOrder AS (
    SELECT
        CustomerID,
        STR_TO_DATE(MIN(OrderDate), '%d-%m-%Y') AS first_order_date
    FROM
        df_ecommerce
    GROUP BY CustomerID
),
CustomerAOV AS (
    SELECT
        CustomerID,
        COUNT(DISTINCT OrderID) AS total_distinct_orders, -- Count of distinct orders
        ROUND(SUM(GrossSales) / COUNT(DISTINCT OrderID), 2) AS average_order_value -- Avg value per order
    FROM
        df_ecommerce
    GROUP BY CustomerID
)
SELECT
    com.CustomerID,
    com.total_line_items,
    com.total_returns,
    com.return_rate,
    com.customer_lifetime_value,
    cao.total_distinct_orders,
    cao.average_order_value,
    DATEDIFF(CURRENT_DATE(), cfo.first_order_date) AS days_since_first_order,
    CASE -- Age Group (assuming Age column exists, you may need to adjust bins)
        WHEN Age < 25 THEN '18-24'
        WHEN Age BETWEEN 25 AND 34 THEN '25-34'
        WHEN Age BETWEEN 35 AND 44 THEN '35-44'
        WHEN Age BETWEEN 45 AND 54 THEN '45-54'
        WHEN Age BETWEEN 55 AND 64 THEN '55-64'
        WHEN Age >= 65 THEN '65+'
        ELSE 'Unknown'
    END AS age_group,
    CASE -- Customer Tenure Segment (adjust bins as per your business logic)
        WHEN DATEDIFF(CURRENT_DATE(), cfo.first_order_date) <= 30 THEN 'New'
        WHEN DATEDIFF(CURRENT_DATE(), cfo.first_order_date) BETWEEN 31 AND 180 THEN 'Regular'
        WHEN DATEDIFF(CURRENT_DATE(), cfo.first_order_date) > 180 THEN 'Loyal'
        ELSE 'Unknown'
    END AS customer_tenure_segment
FROM
    CustomerOverallMetrics com
JOIN
    CustomerFirstOrder cfo ON com.CustomerID = cfo.CustomerID
JOIN
    CustomerAOV cao ON com.CustomerID = cao.CustomerID
LEFT JOIN -- Use LEFT JOIN in case a customer somehow doesn't have an Age or for future expansions
    df_ecommerce e_for_age ON com.CustomerID = e_for_age.CustomerID -- Join back to get Age
GROUP BY -- Grouping for age_group and tenure_segment, ensuring one row per customer
    com.CustomerID,
    com.total_line_items,
    com.total_returns,
    com.return_rate,
    com.customer_lifetime_value,
    cao.total_distinct_orders,
    cao.average_order_value,
    days_since_first_order,
    age_group, -- Include the case expression aliases in GROUP BY
    customer_tenure_segment;