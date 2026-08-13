# 10-day build timeline

The proposal (`docs/` — original PDF, not committed) scopes this as an 8-week
project. This repo builds the same confirmatory family on a 10-day schedule:
each day below is one focused commit, reviewed before moving to the next.

| Day | Milestone | Proposal ref |
|---|---|---|
| 1 | Research questions, analysis plan, treatment classification table (**done**) | Week 1 |
| 2 | Pull real FRED/QCEW data; source-check treatment table against DOL/NCSL; scaffold the CPS-ORG pull (blocked on an IPUMS API key) | Week 2 |
| 3 | Exposure measure from CPS-ORG; QCEW correlation validation check; exposure-distribution check | Week 2-3 |
| 4 | Simple linear regression (§7) and multiple regression (§6.1) | Week 4 |
| 5 | Model A (binary DiD) and Model C (exposure interaction), both industries | Week 5 |
| 7 | Event study / parallel-trends check; COVID-sensitivity covariate spec | Week 6-7 |
| 8 | Placebo test; cluster bootstrap for β₄; model diagnostics | Week 7 |
| 9 | Two-sample t-test; descriptive statistics; one-way regional ANOVA; Monte Carlo permutation | Week 8 |
| 10 | Final R Markdown report, README pass, reproducibility check | Week 8 |

**Blocked step:** Day 2's CPS-ORG pull needs an `IPUMS_API_KEY` in a local
`.env` (gitignored, never committed). The pull script will be written and
ready; it won't actually run until that key exists. Until then, downstream
days that need exposure data use clearly-labeled placeholder values so the
pipeline can be built and tested end to end, with a single swap-in point for
the real extract once it lands.

**Power analysis note:** Section 4.4 of the proposal pre-registers this
design as likely underpowered for the exposure-gradient question (β₄) — that
is expected, not a bug to chase, and Day 3's power simulation exists to state
that limit honestly rather than to "fix" it.
