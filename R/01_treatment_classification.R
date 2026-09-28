# Load and validate the state minimum-wage treatment classification table.
#
# NOTE ON DATA PROVENANCE: the 2020/2021 wage values in
# data/treatment_classification.csv have been cross-checked against DOL's
# "Minimum Wage Laws in the States" table, using two Wayback Machine
# snapshots of https://www.dol.gov/agencies/whd/minimum-wage/state --
# 2020-12-01 (pre-January-1 rates) and 2021-02-02 (post-January-1 rates).
# All 24 other states matched the draft table exactly. Michigan did not:
# the draft had it going 9.65 -> 9.87, but DOL's Feb 2021 snapshot still
# shows 9.65. Michigan's scheduled increase is conditioned on the prior
# year's unemployment rate staying under 8.5%; the COVID-era unemployment
# spike tripped that clause, so the step was skipped and the rate held at
# 9.65 through all of 2021. The table now reflects that (increase = 0.00,
# type "inflation_adj_paused").
#
# Michigan is a control: treatment is an actual 2021 increase, not a
# scheduled increase that never took effect. This gives 19 treated,
# 26 control and 5 excluded states; 9 treated increases are below $0.50.
# Confirmation: Michigan LEO's December 2, 2021 announcement describes
# the 2022 increase from the unchanged $9.65 rate and the 2021 delay:
# https://www.michigan.gov/leo/news/2021/12/02/michigans-minimum-wage-set-to-increase-on-january-1-2022
# Classification concerns 2021 only; later policy changes remain a
# limitation when interpreting outcomes through 2022.

library(dplyr)
library(readr)

load_treatment_table <- function(path = "data/treatment_classification.csv") {
  read_csv(path, col_types = cols(
    state = col_character(),
    wage_2020 = col_double(),
    wage_2021 = col_double(),
    effective_date = col_date(),
    increase = col_double(),
    increase_type = col_character(),
    group = col_character()
  ))
}

validate_treatment_table <- function(df) {
  problems <- character(0)

  if (n_distinct(df$state) != nrow(df)) {
    problems <- c(problems, "duplicate state rows")
  }

  computed <- round(df$wage_2021 - df$wage_2020, 2)
  mismatch <- df$state[abs(computed - df$increase) > 0.005]
  if (length(mismatch) > 0) {
    problems <- c(problems, paste("increase column doesn't match wage_2021 - wage_2020 for:",
                                   paste(mismatch, collapse = ", ")))
  }

  if (any(df$group == "treated" & (is.na(df$increase) | df$increase <= 0))) {
    problems <- c(problems, "treated states must have a positive increase")
  }
  if (any(df$group == "control" & (is.na(df$increase) | df$increase != 0))) {
    problems <- c(problems, "control states must have zero increase")
  }

  bad_groups <- setdiff(unique(df$group), c("treated", "excluded", "control"))
  if (length(bad_groups) > 0) {
    problems <- c(problems, paste("unexpected group values:", paste(bad_groups, collapse = ", ")))
  }

  problems
}

if (sys.nframe() == 0) {
  df <- load_treatment_table()
  problems <- validate_treatment_table(df)

  if (length(problems) > 0) {
    stop("Treatment table validation failed:\n", paste("-", problems, collapse = "\n"))
  }

  cat("Treated states:", sum(df$group == "treated"), "\n")
  cat("Excluded/secondary states:", sum(df$group == "excluded"), "\n")
  cat("Control states:", sum(df$group == "control"), "\n")
  cat("Treated states below $0.50 increase (sensitivity threshold):",
      sum(df$group == "treated" & df$increase < 0.50), "\n")
}
