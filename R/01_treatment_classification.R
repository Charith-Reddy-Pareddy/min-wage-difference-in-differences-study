# Load and validate the state minimum-wage treatment classification table.
#
# NOTE ON DATA PROVENANCE: the 2020/2021 wage values in
# data/treatment_classification.csv were compiled from general knowledge of
# state minimum wage history, not pulled directly from DOL/NCSL. Section 3
# of the proposal calls for cross-checking against DOL and NCSL directly --
# do that before these numbers are used in any real analysis. Day 3
# (data acquisition) replaces this with a sourced pull.

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
