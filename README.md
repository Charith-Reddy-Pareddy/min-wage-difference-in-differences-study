# State Minimum Wage Increases and Low-Wage Employment

A difference-in-differences study of the 2021 round of state minimum wage
increases, extended beyond a single average treatment effect to ask how the
employment response varies with pre-policy wage exposure.

## Research questions

**Primary:** How does the employment response to state minimum-wage
increases vary with pre-policy minimum-wage exposure across low-wage
industries?

**Secondary:**
1. Does minimum-wage treatment affect employment in food service and retail?
2. Is the effect larger where exposure is greater?
3. Does the effect differ across Census regions?
4. How sensitive are these conclusions to alternative treatment definitions
   and inference procedures?

This builds on a standard Card-Krueger-style state minimum wage DiD design.
The contribution isn't a new question but a specific empirical angle: moving
from one average treatment effect to modeling how that effect scales with
exposure.

## Data sources

| Source | Role |
|---|---|
| FRED | State-quarter employment (food service, retail), GDP, population |
| U.S. DOL (cross-checked against NCSL) | Treatment classification (wage change dates/amounts) |
| QCEW wage-band tables / CPS ORG (IPUMS-CPS) | Exposure measure construction |
| CPS (IPUMS-CPS) | Teen employment (16-19), secondary outcome |

## Repo layout

```
data/raw/        source pulls, not committed (see .gitignore)
data/processed/  cleaned panel data, not committed
R/               data prep and analysis scripts
reports/         R Markdown report and figures
```

## Status

Early setup. Treatment classification and data pull scripts are next.
