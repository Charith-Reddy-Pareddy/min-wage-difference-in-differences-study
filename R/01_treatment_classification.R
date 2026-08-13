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
# That correction does NOT change the 20-treated-states count (Michigan
# stays in the treated group, per the proposal's explicit state list -- it
# still "raised wages" on the proposal's own binary definition, it just
# raised them by $0). It also doesn't change the below-$0.50-threshold
# count: Michigan was already counted there at $0.22, and $0.00 is still
# under $0.50, so the count stays at 10. The proposal text's claim of "9
# of the 20 states" below that threshold appears to be a minor error in
# the proposal narrative itself, not a data problem in this table -- 10 is
# what a direct DOL source check supports.

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

  n_treated <- sum(df$group == "treated")
  if (n_treated != 20) {
    problems <- c(problems, paste("expected 20 treated states, found", n_treated))
  }

  bad_groups <- setdiff(unique(df$group), c("treated", "excluded"))
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
  cat("Treated states below $0.50 increase (sensitivity threshold):",
      sum(df$group == "treated" & df$increase < 0.50), "\n")
}
