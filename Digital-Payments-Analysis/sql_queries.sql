-- ====================================================================
-- Digital Payments Analytics - SQL Query Library
-- ====================================================================
-- 
-- Collection of optimized SQL queries for analyzing payment transaction
-- data, user behavior, and channel performance.
--
-- Database: PostgreSQL 12+ or MySQL 8.0+
-- Author: Irfan Khan
-- Date: 2025-10-22
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. ADOPTION METRICS
-- --------------------------------------------------------------------

-- Daily Active Users (DAU)
SELECT 
    DATE(transaction_date) AS date,
    COUNT(DISTINCT user_id) AS dau,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_value,
    ROUND(AVG(amount), 2) AS avg_transaction_value
FROM transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '30 days'
    AND status = 'completed'
GROUP BY DATE(transaction_date)
ORDER BY date DESC;

-- Monthly Active Users (MAU) Trend
SELECT 
    DATE_TRUNC('month', transaction_date) AS month,
    COUNT(DISTINCT user_id) AS mau,
    COUNT(*) AS transactions,
    SUM(amount) AS total_value,
    ROUND(COUNT(*)::DECIMAL / COUNT(DISTINCT user_id), 2) AS transactions_per_user
FROM transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '12 months'
    AND status = 'completed'
GROUP BY DATE_TRUNC('month', transaction_date)
ORDER BY month;

-- Growth Rates (MoM and YoY)
WITH monthly_metrics AS (
    SELECT 
        DATE_TRUNC('month', transaction_date) AS month,
        COUNT(DISTINCT user_id) AS active_users,
        COUNT(*) AS transaction_count,
        SUM(amount) AS total_value
    FROM transactions
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', transaction_date)
)
SELECT 
    month,
    active_users,
    transaction_count,
    total_value,
    ROUND(
        (active_users - LAG(active_users, 1) OVER (ORDER BY month))::DECIMAL 
        / NULLIF(LAG(active_users, 1) OVER (ORDER BY month), 0) * 100, 
        2
    ) AS user_growth_mom_pct,
    ROUND(
        (transaction_count - LAG(transaction_count, 1) OVER (ORDER BY month))::DECIMAL 
        / NULLIF(LAG(transaction_count, 1) OVER (ORDER BY month), 0) * 100, 
        2
    ) AS txn_growth_mom_pct,
    ROUND(
        (active_users - LAG(active_users, 12) OVER (ORDER BY month))::DECIMAL 
        / NULLIF(LAG(active_users, 12) OVER (ORDER BY month), 0) * 100, 
        2
    ) AS user_growth_yoy_pct
FROM monthly_metrics
ORDER BY month DESC;

-- --------------------------------------------------------------------
-- 2. CHANNEL PERFORMANCE ANALYSIS
-- --------------------------------------------------------------------

-- Channel Adoption and Performance
SELECT 
    channel,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_value,
    ROUND(AVG(amount), 2) AS avg_transaction_value,
    ROUND(STDDEV(amount), 2) AS stddev_value,
    ROUND(
        COUNT(*)::DECIMAL / SUM(COUNT(*)) OVER () * 100, 
        2
    ) AS pct_of_transactions,
    ROUND(
        SUM(amount)::DECIMAL / SUM(SUM(amount)) OVER () * 100, 
        2
    ) AS pct_of_value
FROM transactions
WHERE status = 'completed'
    AND transaction_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY channel
ORDER BY transaction_count DESC;

-- Channel Growth Trends
SELECT 
    DATE_TRUNC('month', transaction_date) AS month,
    channel,
    COUNT(DISTINCT user_id) AS active_users,
    COUNT(*) AS transactions,
    SUM(amount) AS total_value
FROM transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '12 months'
    AND status = 'completed'
GROUP BY DATE_TRUNC('month', transaction_date), channel
ORDER BY month DESC, channel;

-- Cross-Channel Usage
WITH user_channels AS (
    SELECT 
        user_id,
        COUNT(DISTINCT channel) AS channels_used,
        STRING_AGG(DISTINCT channel, ', ' ORDER BY channel) AS channel_list
    FROM transactions
    WHERE transaction_date >= CURRENT_DATE - INTERVAL '90 days'
        AND status = 'completed'
    GROUP BY user_id
)
SELECT 
    channels_used,
    COUNT(*) AS user_count,
    ROUND(COUNT(*)::DECIMAL / SUM(COUNT(*)) OVER () * 100, 2) AS pct_users
FROM user_channels
GROUP BY channels_used
ORDER BY channels_used;

-- --------------------------------------------------------------------
-- 3. RFM ANALYSIS (SQL Implementation)
-- --------------------------------------------------------------------

-- Calculate RFM Scores
WITH rfm_calc AS (
    SELECT 
        user_id,
        CURRENT_DATE - MAX(DATE(transaction_date)) AS recency_days,
        COUNT(*) AS frequency,
        SUM(amount) AS monetary
    FROM transactions
    WHERE transaction_date >= CURRENT_DATE - INTERVAL '365 days'
        AND status = 'completed'
    GROUP BY user_id
),
rfm_scores AS (
    SELECT 
        user_id,
        recency_days,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency) AS f_score,
        NTILE(4) OVER (ORDER BY monetary) AS m_score
    FROM rfm_calc
)
SELECT 
    user_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_score,
    CONCAT(r_score, f_score, m_score) AS rfm_segment,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN f_score >= 4 AND m_score >= 3 AND r_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN m_score >= 4 AND r_score <= 2 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 2 THEN 'Hibernating'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Others'
    END AS segment_name
FROM rfm_scores
ORDER BY rfm_score DESC;

-- RFM Segment Summary
WITH rfm_segments AS (
    -- Use the RFM query from above as CTE
    SELECT 
        user_id,
        recency_days,
        frequency,
        monetary,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN f_score >= 4 AND m_score >= 3 AND r_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 3 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN m_score >= 4 AND r_score <= 2 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 2 THEN 'Hibernating'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
            ELSE 'Others'
        END AS segment_name
    FROM (
        SELECT 
            user_id,
            recency_days,
            frequency,
            monetary,
            NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,
            NTILE(4) OVER (ORDER BY frequency) AS f_score,
            NTILE(4) OVER (ORDER BY monetary) AS m_score
        FROM (
            SELECT 
                user_id,
                CURRENT_DATE - MAX(DATE(transaction_date)) AS recency_days,
                COUNT(*) AS frequency,
                SUM(amount) AS monetary
            FROM transactions
            WHERE transaction_date >= CURRENT_DATE - INTERVAL '365 days'
                AND status = 'completed'
            GROUP BY user_id
        ) rfm_base
    ) rfm_scored
)
SELECT 
    segment_name,
    COUNT(*) AS user_count,
    ROUND(AVG(recency_days), 1) AS avg_recency,
    ROUND(AVG(frequency), 1) AS avg_frequency,
    ROUND(AVG(monetary), 2) AS avg_monetary,
    SUM(monetary) AS total_value,
    ROUND(COUNT(*)::DECIMAL / SUM(COUNT(*)) OVER () * 100, 2) AS pct_users,
    ROUND(SUM(monetary)::DECIMAL / SUM(SUM(monetary)) OVER () * 100, 2) AS pct_value
FROM rfm_segments
GROUP BY segment_name
ORDER BY user_count DESC;

-- --------------------------------------------------------------------
-- 4. COHORT ANALYSIS
-- --------------------------------------------------------------------

-- Monthly Cohort Retention
WITH user_cohorts AS (
    SELECT 
        user_id,
        DATE_TRUNC('month', MIN(transaction_date)) AS cohort_month
    FROM transactions
    WHERE status = 'completed'
    GROUP BY user_id
),
cohort_activity AS (
    SELECT 
        uc.cohort_month,
        DATE_TRUNC('month', t.transaction_date) AS activity_month,
        COUNT(DISTINCT t.user_id) AS active_users
    FROM user_cohorts uc
    JOIN transactions t ON uc.user_id = t.user_id
    WHERE t.status = 'completed'
    GROUP BY uc.cohort_month, DATE_TRUNC('month', t.transaction_date)
),
cohort_sizes AS (
    SELECT 
        cohort_month,
        COUNT(*) AS cohort_size
    FROM user_cohorts
    GROUP BY cohort_month
)
SELECT 
    ca.cohort_month,
    cs.cohort_size,
    ca.activity_month,
    EXTRACT(MONTH FROM AGE(ca.activity_month, ca.cohort_month)) AS months_since_cohort,
    ca.active_users,
    ROUND(ca.active_users::DECIMAL / cs.cohort_size * 100, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
WHERE ca.cohort_month >= CURRENT_DATE - INTERVAL '12 months'
ORDER BY ca.cohort_month, ca.activity_month;

-- Cohort Retention Pivot (for visualization)
WITH retention_data AS (
    -- Same as cohort_activity above
    SELECT 
        ca.cohort_month,
        EXTRACT(MONTH FROM AGE(ca.activity_month, ca.cohort_month)) AS period,
        ROUND(ca.active_users::DECIMAL / cs.cohort_size * 100, 2) AS retention_pct
    FROM cohort_activity ca
    JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
)
SELECT 
    cohort_month,
    MAX(CASE WHEN period = 0 THEN retention_pct END) AS month_0,
    MAX(CASE WHEN period = 1 THEN retention_pct END) AS month_1,
    MAX(CASE WHEN period = 2 THEN retention_pct END) AS month_2,
    MAX(CASE WHEN period = 3 THEN retention_pct END) AS month_3,
    MAX(CASE WHEN period = 6 THEN retention_pct END) AS month_6,
    MAX(CASE WHEN period = 12 THEN retention_pct END) AS month_12
FROM retention_data
GROUP BY cohort_month
ORDER BY cohort_month DESC;

-- --------------------------------------------------------------------
-- 5. ADOPTION GAP ANALYSIS
-- --------------------------------------------------------------------

-- Feature Adoption by User Segment
SELECT 
    u.age_group,
    u.region,
    COUNT(DISTINCT u.user_id) AS total_users,
    COUNT(DISTINCT CASE WHEN t.channel = 'mobile_app' THEN t.user_id END) AS mobile_users,
    COUNT(DISTINCT CASE WHEN t.channel = 'peer_to_peer' THEN t.user_id END) AS p2p_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN t.channel = 'mobile_app' THEN t.user_id END)::DECIMAL 
        / COUNT(DISTINCT u.user_id) * 100, 
        2
    ) AS mobile_adoption_pct,
    ROUND(
        COUNT(DISTINCT CASE WHEN t.channel = 'peer_to_peer' THEN t.user_id END)::DECIMAL 
        / COUNT(DISTINCT u.user_id) * 100, 
        2
    ) AS p2p_adoption_pct
FROM users u
LEFT JOIN transactions t ON u.user_id = t.user_id 
    AND t.transaction_date >= CURRENT_DATE - INTERVAL '90 days'
    AND t.status = 'completed'
GROUP BY u.age_group, u.region
ORDER BY total_users DESC;

-- Opportunity Sizing
WITH segment_metrics AS (
    SELECT 
        u.region,
        COUNT(DISTINCT u.user_id) AS total_users,
        COALESCE(AVG(user_txns.txn_count), 0) AS avg_transactions,
        COALESCE(AVG(user_txns.total_spent), 0) AS avg_spending
    FROM users u
    LEFT JOIN (
        SELECT 
            user_id,
            COUNT(*) AS txn_count,
            SUM(amount) AS total_spent
        FROM transactions
        WHERE transaction_date >= CURRENT_DATE - INTERVAL '90 days'
            AND status = 'completed'
        GROUP BY user_id
    ) user_txns ON u.user_id = user_txns.user_id
    GROUP BY u.region
),
overall_avg AS (
    SELECT 
        AVG(avg_transactions) AS platform_avg_txns,
        AVG(avg_spending) AS platform_avg_spending
    FROM segment_metrics
)
SELECT 
    sm.region,
    sm.total_users,
    ROUND(sm.avg_transactions, 2) AS avg_transactions,
    ROUND(sm.avg_spending, 2) AS avg_spending,
    ROUND(oa.platform_avg_txns - sm.avg_transactions, 2) AS gap_transactions,
    ROUND(
        (oa.platform_avg_txns - sm.avg_transactions) * sm.total_users, 
        0
    ) AS opportunity_transactions,
    ROUND(
        (oa.platform_avg_spending - sm.avg_spending) * sm.total_users, 
        2
    ) AS opportunity_value
FROM segment_metrics sm
CROSS JOIN overall_avg oa
WHERE sm.avg_transactions < oa.platform_avg_txns
ORDER BY opportunity_value DESC;

-- --------------------------------------------------------------------
-- 6. CHURN PREDICTION
-- --------------------------------------------------------------------

-- At-Risk Users (Declining Activity)
WITH user_activity AS (
    SELECT 
        user_id,
        COUNT(*) AS total_transactions,
        MAX(DATE(transaction_date)) AS last_transaction_date,
        CURRENT_DATE - MAX(DATE(transaction_date)) AS days_since_last,
        COUNT(CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS last_30_days,
        COUNT(CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '60 days' 
                   AND transaction_date < CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS prev_30_days
    FROM transactions
    WHERE transaction_date >= CURRENT_DATE - INTERVAL '180 days'
        AND status = 'completed'
    GROUP BY user_id
)
SELECT 
    user_id,
    total_transactions,
    last_transaction_date,
    days_since_last,
    last_30_days,
    prev_30_days,
    CASE 
        WHEN days_since_last > 60 AND total_transactions >= 5 THEN 'High Risk'
        WHEN days_since_last > 30 AND prev_30_days > last_30_days THEN 'Medium Risk'
        WHEN last_30_days < prev_30_days * 0.5 THEN 'Low Risk'
        ELSE 'Not At Risk'
    END AS risk_level
FROM user_activity
WHERE total_transactions >= 3
ORDER BY days_since_last DESC, total_transactions DESC;

-- --------------------------------------------------------------------
-- 7. EXECUTIVE DASHBOARD QUERIES
-- --------------------------------------------------------------------

-- Key Performance Indicators (KPIs)
SELECT 
    -- User metrics
    COUNT(DISTINCT user_id) AS total_active_users,
    COUNT(DISTINCT CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '30 days' 
          THEN user_id END) AS mau,
    COUNT(DISTINCT CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '7 days' 
          THEN user_id END) AS wau,
    
    -- Transaction metrics
    COUNT(*) AS total_transactions,
    SUM(amount) AS total_value,
    ROUND(AVG(amount), 2) AS avg_transaction_value,
    
    -- Growth metrics
    ROUND(
        (COUNT(DISTINCT CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '30 days' 
               THEN user_id END)::DECIMAL -
         COUNT(DISTINCT CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '60 days' 
                            AND transaction_date < CURRENT_DATE - INTERVAL '30 days' 
               THEN user_id END)) /
        NULLIF(COUNT(DISTINCT CASE WHEN transaction_date >= CURRENT_DATE - INTERVAL '60 days' 
                                  AND transaction_date < CURRENT_DATE - INTERVAL '30 days' 
               THEN user_id END), 0) * 100,
        2
    ) AS mau_growth_mom_pct
FROM transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '90 days'
    AND status = 'completed';

-- Top Performing Segments
SELECT 
    merchant_category,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_value,
    COUNT(DISTINCT user_id) AS unique_users,
    ROUND(AVG(amount), 2) AS avg_transaction_value
FROM transactions
WHERE transaction_date >= CURRENT_DATE - INTERVAL '30 days'
    AND status = 'completed'
GROUP BY merchant_category
ORDER BY total_value DESC
LIMIT 10;

-- --------------------------------------------------------------------
-- 8. MATERIALIZED VIEWS (for Performance)
-- --------------------------------------------------------------------

-- Create materialized view for daily metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_metrics AS
SELECT 
    DATE(transaction_date) AS date,
    COUNT(DISTINCT user_id) AS dau,
    COUNT(*) AS transactions,
    SUM(amount) AS total_value,
    AVG(amount) AS avg_value
FROM transactions
WHERE status = 'completed'
GROUP BY DATE(transaction_date);

-- Refresh command (run daily)
-- REFRESH MATERIALIZED VIEW daily_metrics;

-- Create materialized view for user segments
CREATE MATERIALIZED VIEW IF NOT EXISTS user_rfm_segments AS
WITH rfm_calc AS (
    SELECT 
        user_id,
        CURRENT_DATE - MAX(DATE(transaction_date)) AS recency_days,
        COUNT(*) AS frequency,
        SUM(amount) AS monetary
    FROM transactions
    WHERE transaction_date >= CURRENT_DATE - INTERVAL '365 days'
        AND status = 'completed'
    GROUP BY user_id
),
rfm_scores AS (
    SELECT 
        user_id,
        recency_days,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency) AS f_score,
        NTILE(4) OVER (ORDER BY monetary) AS m_score
    FROM rfm_calc
)
SELECT 
    user_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN f_score >= 4 AND m_score >= 3 AND r_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN m_score >= 4 AND r_score <= 2 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 2 THEN 'Hibernating'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Others'
    END AS segment_name
FROM rfm_scores;

-- Refresh command (run weekly)
-- REFRESH MATERIALIZED VIEW user_rfm_segments;
