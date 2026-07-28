-- =============================================================================
-- FILE        : 02_analysis.sql
-- PROJECT     : Fintech Loan Application A/B Test
-- DESCRIPTION : SQL analysis layer — segmentation, funnel analysis, and
--               pre-statistical checks before running the Python test.
--               Compatible with Snowflake, PostgreSQL, and BigQuery.
-- =============================================================================


-- =============================================================================
-- SECTION 1 — SCHEMA
-- =============================================================================

CREATE TABLE ab_test_users (
    user_id                  VARCHAR(12)   PRIMARY KEY,
    experiment_id            VARCHAR(20),
    group                    VARCHAR(20),       -- 'control' or 'treatment'
    variant                  VARCHAR(30),       -- 'A_control_5step' or 'B_treatment_3step'
    device                   VARCHAR(10),
    age_group                VARCHAR(10),
    income_band              VARCHAR(10),
    traffic_source           VARCHAR(20),
    loan_purpose             VARCHAR(30),
    loan_amount_requested    DECIMAL(10,2),
    experiment_start_ts      TIMESTAMP,
    form_submitted           BOOLEAN,
    last_step_reached        INT,
    total_steps              INT,
    time_on_form_secs        INT,
    submission_ts            TIMESTAMP
);

CREATE TABLE ab_test_events (
    event_id      VARCHAR(14)   PRIMARY KEY,
    user_id       VARCHAR(12)   REFERENCES ab_test_users(user_id),
    group         VARCHAR(20),
    step_number   INT,
    event_type    VARCHAR(20),  -- step_completed, step_abandoned, form_submitted
    event_ts      TIMESTAMP,
    device        VARCHAR(10)
);


-- =============================================================================
-- SECTION 2 — SANITY CHECKS (run before any analysis)
-- Ensures randomisation worked and the test is valid.
-- =============================================================================

-- 2a. Group size balance — should be roughly 50/50
SELECT
    "group",
    COUNT(*)                                        AS n_users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM ab_test_users
GROUP BY "group"
ORDER BY "group";

-- 2b. Check for sample ratio mismatch (SRM)
-- If one group is >55% of total, randomisation may be broken
WITH counts AS (
    SELECT
        COUNT(CASE WHEN "group" = 'control'   THEN 1 END) AS n_control,
        COUNT(CASE WHEN "group" = 'treatment' THEN 1 END) AS n_treatment,
        COUNT(*) AS n_total
    FROM ab_test_users
)
SELECT
    n_control,
    n_treatment,
    n_total,
    ROUND(100.0 * n_control   / n_total, 1) AS pct_control,
    ROUND(100.0 * n_treatment / n_total, 1) AS pct_treatment,
    CASE
        WHEN ABS(n_control - n_treatment) * 1.0 / n_total > 0.05
        THEN 'WARNING — possible sample ratio mismatch'
        ELSE 'OK — groups are balanced'
    END AS srm_check
FROM counts;

-- 2c. Device distribution by group — should be similar
-- A large difference indicates non-random assignment
SELECT
    "group",
    device,
    COUNT(*)                                            AS n_users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY "group"), 1) AS pct_within_group
FROM ab_test_users
GROUP BY "group", device
ORDER BY "group", pct_within_group DESC;

-- 2d. Traffic source balance
SELECT
    "group",
    traffic_source,
    COUNT(*)                                            AS n_users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY "group"), 1) AS pct_within_group
FROM ab_test_users
GROUP BY "group", traffic_source
ORDER BY "group", n_users DESC;


-- =============================================================================
-- SECTION 3 — PRIMARY METRIC: APPLICATION COMPLETION RATE
-- =============================================================================

-- 3a. Top-level conversion rate by group
SELECT
    "group",
    variant,
    COUNT(*)                                           AS total_users,
    SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END)   AS submitted,
    ROUND(
        100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2
    )                                                  AS conversion_rate_pct,
    ROUND(AVG(time_on_form_secs) / 60.0, 1)           AS avg_time_on_form_mins
FROM ab_test_users
GROUP BY "group", variant
ORDER BY "group";

-- 3b. Absolute and relative uplift
WITH rates AS (
    SELECT
        "group",
        COUNT(*)                                               AS n,
        SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END)       AS conversions,
        ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 4) AS rate
    FROM ab_test_users
    GROUP BY "group"
)
SELECT
    MAX(CASE WHEN "group" = 'control'   THEN rate END)          AS control_rate,
    MAX(CASE WHEN "group" = 'treatment' THEN rate END)          AS treatment_rate,
    ROUND(
        MAX(CASE WHEN "group" = 'treatment' THEN rate END) -
        MAX(CASE WHEN "group" = 'control'   THEN rate END), 4
    )                                                           AS absolute_uplift_pp,
    ROUND(
        100.0 * (
            MAX(CASE WHEN "group" = 'treatment' THEN rate END) -
            MAX(CASE WHEN "group" = 'control'   THEN rate END)
        ) / NULLIF(MAX(CASE WHEN "group" = 'control' THEN rate END), 0), 2
    )                                                           AS relative_uplift_pct
FROM rates;


-- =============================================================================
-- SECTION 4 — FUNNEL ANALYSIS (where do users drop off?)
-- =============================================================================

-- 4a. Step-by-step drop-off by group
WITH step_counts AS (
    SELECT
        "group",
        step_number,
        COUNT(DISTINCT user_id)                        AS users_reached,
        SUM(CASE WHEN event_type = 'step_abandoned'
                      OR event_type = 'step_completed'
                 THEN 1 ELSE 0 END)                    AS users_at_step,
        SUM(CASE WHEN event_type IN ('step_abandoned') THEN 1 ELSE 0 END)  AS dropped_at_step
    FROM ab_test_events
    GROUP BY "group", step_number
),
with_pct AS (
    SELECT
        "group",
        step_number,
        users_reached,
        dropped_at_step,
        ROUND(100.0 * dropped_at_step / NULLIF(users_reached, 0), 1) AS drop_rate_pct,
        ROUND(100.0 * users_reached /
              FIRST_VALUE(users_reached) OVER (PARTITION BY "group" ORDER BY step_number), 1
        ) AS pct_of_starters
    FROM step_counts
)
SELECT * FROM with_pct
ORDER BY "group", step_number;

-- 4b. Funnel completion summary — how many users make it all the way through
SELECT
    "group",
    COUNT(*)                                                    AS entered_funnel,
    SUM(CASE WHEN last_step_reached >= 1 THEN 1 ELSE 0 END)    AS reached_step_1,
    SUM(CASE WHEN last_step_reached >= 2 THEN 1 ELSE 0 END)    AS reached_step_2,
    SUM(CASE WHEN last_step_reached >= 3 THEN 1 ELSE 0 END)    AS reached_step_3,
    SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END)            AS submitted
FROM ab_test_users
GROUP BY "group"
ORDER BY "group";


-- =============================================================================
-- SECTION 5 — SEGMENTATION ANALYSIS
-- Breaks conversion rates down by key user attributes.
-- Finds where the treatment effect is strongest.
-- =============================================================================

-- 5a. Conversion by device — key question: does the 3-step help mobile most?
SELECT
    "group",
    device,
    COUNT(*)                                                    AS n_users,
    SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END)            AS conversions,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM ab_test_users
GROUP BY "group", device
ORDER BY device, "group";

-- 5b. Conversion by age group
SELECT
    "group",
    age_group,
    COUNT(*)                                                    AS n_users,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM ab_test_users
GROUP BY "group", age_group
ORDER BY age_group, "group";

-- 5c. Conversion by income band — higher earners may complete regardless
SELECT
    "group",
    income_band,
    COUNT(*)                                                    AS n_users,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct,
    ROUND(AVG(loan_amount_requested), 0)                        AS avg_loan_requested
FROM ab_test_users
GROUP BY "group", income_band
ORDER BY income_band, "group";

-- 5d. Conversion by traffic source — does intent level matter?
SELECT
    "group",
    traffic_source,
    COUNT(*)                                                    AS n_users,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM ab_test_users
GROUP BY "group", traffic_source
ORDER BY traffic_source, "group";

-- 5e. Loan purpose breakdown — any purpose-specific effects?
SELECT
    "group",
    loan_purpose,
    COUNT(*)                                                    AS n_users,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM ab_test_users
GROUP BY "group", loan_purpose
ORDER BY loan_purpose, "group";


-- =============================================================================
-- SECTION 6 — SECONDARY METRICS
-- =============================================================================

-- 6a. Time on form distribution by group and device
SELECT
    "group",
    device,
    COUNT(*)                                            AS n_users,
    ROUND(AVG(time_on_form_secs) / 60.0, 1)            AS avg_mins,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY time_on_form_secs) / 60.0, 1)      AS median_mins,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP
          (ORDER BY time_on_form_secs) / 60.0, 1)      AS p25_mins,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
          (ORDER BY time_on_form_secs) / 60.0, 1)      AS p75_mins
FROM ab_test_users
GROUP BY "group", device
ORDER BY device, "group";

-- 6b. Loan amount requested by submitters — does the form change drive better-quality applicants?
SELECT
    "group",
    COUNT(*)                                            AS submitted_applications,
    ROUND(AVG(loan_amount_requested), 0)                AS avg_loan_amount,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY loan_amount_requested), 0)          AS median_loan_amount,
    ROUND(SUM(loan_amount_requested), 0)                AS total_loan_volume
FROM ab_test_users
WHERE form_submitted = TRUE
GROUP BY "group"
ORDER BY "group";

-- 6c. Daily submission trend — checks for novelty effect
-- (conversion rate should be stable over time, not just high in week 1)
SELECT
    DATE_TRUNC('week', experiment_start_ts)             AS week_start,
    "group",
    COUNT(*)                                            AS users,
    SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END)    AS submissions,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS weekly_conversion_pct
FROM ab_test_users
GROUP BY DATE_TRUNC('week', experiment_start_ts), "group"
ORDER BY week_start, "group";


-- =============================================================================
-- SECTION 7 — NOVELTY EFFECT CHECK
-- Conversion rate in week 1 vs weeks 2–8 — if week 1 is unusually high
-- for treatment, the effect may be novelty, not genuine improvement.
-- =============================================================================

WITH weekly_conv AS (
    SELECT
        "group",
        CASE
            WHEN DATE_TRUNC('week', experiment_start_ts) =
                 DATE_TRUNC('week', MIN(experiment_start_ts) OVER ())
            THEN 'week_1'
            ELSE 'weeks_2_plus'
        END AS period,
        form_submitted
    FROM ab_test_users
)
SELECT
    "group",
    period,
    COUNT(*)                                                AS n_users,
    ROUND(100.0 * SUM(CASE WHEN form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM weekly_conv
GROUP BY "group", period
ORDER BY period, "group";


-- =============================================================================
-- SECTION 8 — EXECUTIVE SUMMARY VIEW
-- One-row-per-group summary for the business recommendation slide.
-- =============================================================================

SELECT
    u."group"                                                   AS experiment_group,
    u.variant,
    COUNT(DISTINCT u.user_id)                                   AS total_users,
    SUM(CASE WHEN u.form_submitted THEN 1 ELSE 0 END)           AS total_submissions,
    ROUND(100.0 * SUM(CASE WHEN u.form_submitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct,
    ROUND(AVG(u.time_on_form_secs) / 60.0, 1)                  AS avg_time_on_form_mins,
    ROUND(AVG(CASE WHEN u.form_submitted THEN u.loan_amount_requested END), 0) AS avg_loan_requested,
    ROUND(SUM(CASE WHEN u.form_submitted THEN u.loan_amount_requested ELSE 0 END), 0) AS total_loan_volume
FROM ab_test_users u
GROUP BY u."group", u.variant
ORDER BY u."group";
