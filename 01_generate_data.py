"""
=============================================================================
FILE        : 01_generate_data.py
PROJECT     : Fintech Loan Application A/B Test
DESCRIPTION : Generates realistic synthetic user-level experiment data
              simulating a 5-step vs 3-step loan application form test.

              Realistic patterns baked in:
              - Treatment group has higher completion rate (the hypothesis)
              - Drop-off probability varies by step (step 2 is hardest)
              - Mobile users drop off more on the 5-step form
              - Time-on-form reflects form complexity
              - Loan amount correlates with income band
=============================================================================
"""

import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta
from pathlib import Path

random.seed(42)
np.random.seed(42)

OUTPUT_DIR = Path("data")
OUTPUT_DIR.mkdir(exist_ok=True)

# ── EXPERIMENT CONFIG ────────────────────────────────────────────────────────
N_USERS          = 10_000       # total users in the experiment
EXPERIMENT_START = datetime(2024, 9, 1)
EXPERIMENT_END   = datetime(2024, 10, 31)
EXPERIMENT_ID    = "EXP-2024-001"

# ── DROP-OFF PROBABILITIES PER STEP ─────────────────────────────────────────
# Control (5-step): probability of completing each step given you started it
CONTROL_STEP_COMPLETION = {
    1: 0.82,   # personal details — high completion, easy
    2: 0.61,   # financial info — hardest step, many drop here
    3: 0.74,   # employment details
    4: 0.80,   # loan preferences
    5: 0.88,   # review & submit
}

# Treatment (3-step): steps are simplified/merged
TREATMENT_STEP_COMPLETION = {
    1: 0.87,   # personal + financial (merged, but pre-filled prompts help)
    2: 0.76,   # employment + loan amount
    3: 0.91,   # review & submit
}

# ── USER ATTRIBUTES ──────────────────────────────────────────────────────────
DEVICES       = ["mobile", "desktop", "tablet"]
DEVICE_W      = [0.54, 0.38, 0.08]

AGE_GROUPS    = ["18-24", "25-34", "35-44", "45-54", "55+"]
AGE_W         = [0.14,   0.31,   0.28,   0.18,   0.09]

INCOME_BANDS  = ["<25k", "25-50k", "50-75k", "75-100k", ">100k"]
INCOME_W      = [0.12,    0.28,    0.32,     0.18,      0.10]

LOAN_PURPOSES = ["debt_consolidation", "home_improvement", "car_purchase",
                 "medical", "education", "business", "other"]
LOAN_PURPOSE_W= [0.28, 0.22, 0.18, 0.10, 0.08, 0.08, 0.06]

TRAFFIC_SOURCES = ["organic", "paid_search", "social", "email", "direct", "referral"]
TRAFFIC_W       = [0.30, 0.25, 0.18, 0.12, 0.10, 0.05]

INCOME_TO_LOAN = {
    "<25k":    (2_000,  8_000),
    "25-50k":  (3_000, 15_000),
    "50-75k":  (5_000, 25_000),
    "75-100k": (8_000, 40_000),
    ">100k":   (10_000, 80_000),
}

def random_timestamp(start, end):
    delta = end - start
    return start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))

def simulate_funnel(group, device, age_group):
    """
    Simulate a user moving through the application funnel.
    Returns last completed step and whether the application was submitted.
    """
    steps = CONTROL_STEP_COMPLETION if group == "control" else TREATMENT_STEP_COMPLETION
    n_steps = len(steps)

    # Mobile users are 12% more likely to drop off on 5-step form
    mobile_penalty = 0.88 if (device == "mobile" and group == "control") else 1.0

    # Older users (55+) complete more carefully on 5-step, slightly lower on 3-step
    age_modifier = 0.95 if (age_group == "55+" and group == "treatment") else 1.0

    last_step = 0
    for step, prob in steps.items():
        adj_prob = min(prob * mobile_penalty * age_modifier, 0.99)
        if random.random() <= adj_prob:
            last_step = step
        else:
            break

    submitted = (last_step == n_steps)
    return last_step, submitted, n_steps

def simulate_time_on_form(group, submitted, device):
    """
    Simulate time spent on the form in seconds.
    3-step form takes ~35% less time on average.
    """
    if group == "control":
        base = np.random.normal(loc=420, scale=90)    # ~7 mins avg
    else:
        base = np.random.normal(loc=270, scale=70)    # ~4.5 mins avg

    # Mobile users are slower on complex forms
    if device == "mobile" and group == "control":
        base *= 1.18

    # Users who don't submit spend less time (dropped off early)
    if not submitted:
        base *= np.random.uniform(0.25, 0.75)

    return max(int(base), 30)

# ── GENERATE USER TABLE ──────────────────────────────────────────────────────
print("Generating users...")
users = []
for i in range(1, N_USERS + 1):
    user_id = f"USR{str(i).zfill(6)}"

    # Hash-based group assignment (deterministic, like real experiments)
    group = "control" if hash(user_id) % 2 == 0 else "treatment"

    device     = random.choices(DEVICES, weights=DEVICE_W)[0]
    age_group  = random.choices(AGE_GROUPS, weights=AGE_W)[0]
    income     = random.choices(INCOME_BANDS, weights=INCOME_W)[0]
    traffic    = random.choices(TRAFFIC_SOURCES, weights=TRAFFIC_W)[0]
    purpose    = random.choices(LOAN_PURPOSES, weights=LOAN_PURPOSE_W)[0]

    lo, hi = INCOME_TO_LOAN[income]
    loan_amt = round(random.uniform(lo, hi), -2)  # round to nearest 100

    ts_start  = random_timestamp(EXPERIMENT_START, EXPERIMENT_END)
    last_step, submitted, n_steps = simulate_funnel(group, device, age_group)
    time_on   = simulate_time_on_form(group, submitted, device)

    ts_submit = (ts_start + timedelta(seconds=time_on)) if submitted else None

    users.append({
        "user_id":          user_id,
        "experiment_id":    EXPERIMENT_ID,
        "group":            group,
        "variant":          "A_control_5step" if group == "control" else "B_treatment_3step",
        "device":           device,
        "age_group":        age_group,
        "income_band":      income,
        "traffic_source":   traffic,
        "loan_purpose":     purpose,
        "loan_amount_requested": loan_amt,
        "experiment_start_ts":  ts_start.isoformat(),
        "form_submitted":   submitted,
        "last_step_reached": last_step,
        "total_steps":      n_steps,
        "time_on_form_secs": time_on,
        "submission_ts":    ts_submit.isoformat() if ts_submit else None,
    })

users_df = pd.DataFrame(users)
users_df.to_csv(OUTPUT_DIR / "ab_test_users.csv", index=False)
print(f"  ab_test_users.csv — {len(users_df):,} rows")

# ── GENERATE EVENT-LEVEL TABLE ───────────────────────────────────────────────
print("Generating step-level events...")
events = []
event_id = 1

for _, row in users_df.iterrows():
    n_steps = row["total_steps"]
    last    = row["last_step_reached"]
    ts      = datetime.fromisoformat(row["experiment_start_ts"])

    for step in range(1, n_steps + 1):
        # Time to complete each step (varies by step complexity)
        step_time = max(int(np.random.normal(
            loc=120 if row["group"] == "control" else 75,
            scale=30
        )), 15)
        ts_step = ts + timedelta(seconds=step_time * step)

        event_type = "step_completed" if step <= last else "step_abandoned"
        if step == last and row["form_submitted"]:
            event_type = "form_submitted"

        events.append({
            "event_id":       f"EVT{str(event_id).zfill(8)}",
            "user_id":        row["user_id"],
            "group":          row["group"],
            "step_number":    step,
            "event_type":     event_type,
            "event_ts":       ts_step.isoformat(),
            "device":         row["device"],
        })
        event_id += 1

        if step > last:
            break

events_df = pd.DataFrame(events)
events_df.to_csv(OUTPUT_DIR / "ab_test_events.csv", index=False)
print(f"  ab_test_events.csv — {len(events_df):,} rows")

# ── QUICK SUMMARY ────────────────────────────────────────────────────────────
print("\n── Experiment summary ──────────────────────────────────────────")
summary = users_df.groupby("group").agg(
    users      = ("user_id", "count"),
    submitted  = ("form_submitted", "sum"),
).reset_index()
summary["conversion_rate"] = (summary["submitted"] / summary["users"] * 100).round(2)
print(summary.to_string(index=False))

ctrl_rate  = summary.loc[summary["group"]=="control",  "conversion_rate"].values[0]
treat_rate = summary.loc[summary["group"]=="treatment","conversion_rate"].values[0]
print(f"\n  Uplift: +{treat_rate - ctrl_rate:.2f}pp ({(treat_rate-ctrl_rate)/ctrl_rate*100:.1f}% relative)")
print("\nData generation complete. Files saved to /data")
