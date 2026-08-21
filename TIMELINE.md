# Build timeline: a 10-day compressed implementation of an 8-week design

The proposal (`docs/` — original PDF, not committed) scopes this as an 8-week
project. This repo compresses the same confirmatory family into a 10-day
schedule: each day below is one focused commit, reviewed before moving to
the next.

| Day | Milestone | Proposal ref |
|---|---|---|
| 1 | Research questions, analysis plan, treatment classification table (**done**) | Week 1 |
| 2 | Pull real FRED/QCEW data; source-check treatment table against DOL/NCSL; scaffold the CPS-ORG pull (**done**) | Week 2 |
| 3 | Exposure measure from CPS-ORG; QCEW correlation validation check; exposure-distribution check (**done**) | Week 2-3 |
| 4 | Simple linear regression (§7) and multiple regression (§6.1) (**done**) | Week 4 |
| 5 | Model A (binary DiD) and Model C (exposure interaction), both industries (**done**) | Week 5 |
| 7 | Event study / parallel-trends check; COVID-sensitivity covariate spec (**done**) | Week 6-7 |
| 8 | Placebo test; cluster bootstrap for β₄; model diagnostics (**done**) | Week 7 |
| 9 | Two-sample t-test; descriptive statistics; one-way regional ANOVA; Monte Carlo permutation (**done**) | Week 8 |
| 10 | Final R Markdown report, README pass, reproducibility check (**done**) | Week 8 |

**Resolved:** the Day 2/3 IPUMS blocker is cleared — a real `IPUMS_API_KEY`
was set locally and the CPS-ORG pull ran for real (Day 3).

**Environment note:** the project moved from `~/Desktop` to `~/Projects`
partway through Day 3 after `~/Desktop`'s iCloud sync (full quota) started
corrupting `.git` objects mid-session. Recovered by re-cloning from GitHub
(which was current through the Day-2 commits) and re-copying the
not-yet-committed Day-3 files over individually with checksum verification.
No history or data was lost, but this is why the repo now lives outside
any iCloud-synced folder.

**Power analysis note:** Section 4.4 of the proposal pre-registers this
design as likely underpowered for the exposure-gradient question (β₄) —
that's expected, not a bug to chase. **Correction, written at the end of
Day 10:** earlier entries in this file said the formal Monte Carlo power
simulation (Section 4.4's `sim_power`, estimating the minimum detectable
effect) was "folded into a later day." It wasn't -- there was no later
day it got folded into, and it was never built. What actually happened is
the *qualitative* pre-registered expectation (design likely underpowered
for β₄) got carried through the write-up and was borne out by the
results (noisy, sign-inconsistent β₄ across every specification), but the
quantitative MDE calculation itself was never run. That's a real gap in
this build, not a rounding error, and it's flagged as such in the final
report's Limitations section rather than left to look like it happened
somewhere it didn't.

**Post-build addition (not one of the 10 days above):** the quantitative
power simulation flagged as missing above was built afterward, in
`R/16_power_analysis.R` — a residual-based Monte Carlo simulation on the
real panel (same method `R/11_cluster_bootstrap.R` already uses). The
proposal's Section 4.4 actually specifies two separate power analyses,
and both are now built:

- **β₃ (Model A, average effect)**, at the proposal's own assumed grid
  of 0.5%/1%/2%/3%: MDE at 80% power isn't reached anywhere in that
  range for either industry. See `reports/figures/power_analysis_beta3.png`
  and `data/processed/power_analysis_beta3_results.csv`.
- **β₄ (Model C, exposure gradient)**: MDE at 80% power is β₄≈0.50 for
  food service and β₄≈0.22 for retail — both well above the actual
  observed estimates (0.167 and -0.005). See `reports/figures/power_analysis.png`
  and `data/processed/power_analysis_results.csv`.

Both confirm the design's qualitative "likely underpowered" expectation
with a number, for both parameters the proposal named.
