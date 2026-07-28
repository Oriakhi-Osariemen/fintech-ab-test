# Fintech Loan Application A/B Test — End-to-End Analysis

A realistic end-to-end A/B test project simulating a fintech lender testing whether simplifying their loan application form from **5 steps to 3 steps** increases completion rates. The project covers the full lifecycle: experiment design, synthetic data generation, SQL-based sanity checks and segmentation, rigorous Python statistical testing, and a structured business recommendation.

---

## The business problem

A fintech lender is losing applicants midway through their loan application. Their UX team hypothesises that a simplified 3-step form will reduce friction and increase completions. A wrong call in either direction is costly:

- **False positive** (shipping a form that doesn't truly perform better): wastes engineering effort, potentially degrades user experience long-term
- **False negative** (not shipping a genuinely better form): leaves significant revenue on the table

This project runs the full statistical analysis to make the right call with confidence.

---

## Experiment design

| Parameter | Value |
|---|---|
| Experiment ID | EXP-2024-001 |
| Period | September 1 – October 31, 2024 |
| Assignment | 50/50 random split via user_id hash |
| Control (Group A) | 5-step form — current design |
| Treatment (Group B) | 3-step form — simplified design |
| Primary metric | Application completion rate |
| Secondary metrics | Time on form, loan amount requested |
| Significance level | α = 0.05 (one-tailed) |
| Minimum detectable effect | 2 percentage points |
| Total users | 10,000 |

**Realistic patterns baked into the synthetic data:**
- Mobile users drop off more on the 5-step form (higher friction)
- Step 2 (financial information) has the highest drop-off rate in the 5-step form
- Time on form reflects form complexity — 3-step averages ~4.5 mins vs ~7 mins
- Loan amount correlates with income band
- Seasonal variation in traffic across the 8-week experiment window

---

## Results

| Metric | Control (A) | Treatment (B) |
|---|---|---|
| Users | 5,078 | 4,922 |
| Submissions | 974 | 2,967 |
| Conversion rate | 19.18% | 60.28% |
| Avg time on form | 4.5 mins | 3.6 mins |
| Absolute uplift | — | +41.10pp |
| Relative uplift | — | +214.3% |
| P-value | — | < 0.0001 |
| 95% CI | — | [+39.4pp, +42.8pp] |

**Decision: SHIP IT** — statistically significant, consistent across all segments, no novelty effect, projected €25M annual revenue uplift.

---

## Project structure

```
fintech-ab-test/
├── data/
│   ├── ab_test_users.csv       # User-level experiment data (10,000 rows)
│   └── ab_test_events.csv      # Step-level event data (26,000+ rows)
├── 01_generate_data.py         # Synthetic data generator
├── 02_analysis.sql             # SQL sanity checks and segmentation
├── 03_statistical_test.py      # Full statistical analysis and recommendation
└── README.md
```

---

## How to run

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/fintech-ab-test.git
cd fintech-ab-test

# 2. Install dependencies
pip install pandas numpy scipy

# 3. Generate synthetic data
python 01_generate_data.py

# 4. Run statistical analysis
python 03_statistical_test.py

# 5. SQL analysis — run 02_analysis.sql in Snowflake, PostgreSQL, or BigQuery
#    (load ab_test_users.csv and ab_test_events.csv first)
```

---

## What the SQL analysis covers (`02_analysis.sql`)

**Section 1 — Schema:** Table definitions for both the user-level and event-level tables.

**Section 2 — Sanity checks:** Before any analysis, validate that randomisation worked:
- Group size balance (sample ratio mismatch check)
- Device distribution by group (should be similar)
- Traffic source balance by group

**Section 3 — Primary metric:** Top-level conversion rate comparison and absolute/relative uplift calculation.

**Section 4 — Funnel analysis:** Step-by-step drop-off rates by group — identifies exactly which step the 5-step form loses users (step 2, financial information).

**Section 5 — Segmentation:** Conversion rates broken down by device, age group, income band, traffic source, and loan purpose. Key finding: the mobile segment shows the largest absolute uplift (+46.7pp).

**Section 6 — Secondary metrics:** Time-on-form distribution by group and device; loan amount analysis for submitted applications.

**Section 7 — Novelty effect check:** Weekly conversion rates to verify the effect is stable over time, not a week-1 spike.

**Section 8 — Executive summary view:** Single-row-per-group summary for the business recommendation.

---

## What the Python analysis covers (`03_statistical_test.py`)

**Section 1 — Sample overview:** Row counts, conversion rates, average form time. Sample ratio mismatch (SRM) check.

**Section 2 — Hypothesis test:** Two-proportion z-test (one-tailed). H₀: the 3-step form does not improve conversion. H₁: it does.

**Section 3 — Effect size and confidence interval:** Absolute and relative uplift with 95% CI. Interpretation of whether the CI includes zero.

**Section 4 — Power analysis:** Observed statistical power, minimum detectable effect, and whether the sample size is sufficient.

**Section 5 — Segmentation analysis:** Z-tests within each key segment (device, age group, income band, traffic source) with Bonferroni correction for multiple comparisons.

**Section 6 — Novelty effect check:** Compares week-1 conversion to later weeks to detect whether the treatment effect is a genuine improvement or just novelty.

**Section 7 — Business impact projection:** Converts the statistical result into projected monthly and annual revenue uplift using realistic assumptions.

**Section 8 — Decision recommendation:** Structured go/no-go recommendation with evidence checklist and next steps.

---

## Statistical concepts demonstrated

- Two-proportion z-test for conversion rate comparison
- One-tailed vs two-tailed test selection and rationale
- P-value interpretation and the difference from "probability of H₀ being true"
- 95% confidence intervals for proportion differences
- Statistical power and minimum sample size calculation
- Sample ratio mismatch (SRM) detection
- Multiple testing problem and Bonferroni correction
- Novelty effect detection via time-series decomposition
- Practical significance vs statistical significance

---

## Key findings

**Primary:** The 3-step form converts at 60.28% vs 19.18% for the 5-step form — a +41.1pp absolute uplift that is highly statistically significant (p < 0.0001, z = 42.05).

**Segmentation:** The effect is consistent across all device types, age groups, income bands, and traffic sources. No segment shows a negative effect, making the rollout decision low-risk.

**Mobile specifically:** The largest uplift is on mobile (+46.7pp) — the 5-step form is especially punishing on small screens. This also suggests a follow-on experiment: a mobile-first form redesign.

**Loan quality:** Average loan amount requested is similar between groups (€16,900 control vs €17,000 treatment), meaning the 3-step form is not attracting lower-quality applicants — just more of them.

---

## Related project

The SQL schema and analytical patterns in this project complement the companion project:
**[pharma-inventory-sql](https://github.com/YOUR_USERNAME/pharma-inventory-sql)** — a separate SQL portfolio project demonstrating inventory analytics.

---

## Author

Osariemen Oriakhi — Data & Finance Analyst, Paris
[LinkedIn](https://linkedin.com/in/your-profile) · [GitHub](https://github.com/your-username)
