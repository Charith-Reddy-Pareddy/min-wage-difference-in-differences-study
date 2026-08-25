# Post-build addition: Section 8 (Multiple Testing and Inferential
# Hierarchy) names the confirmatory family explicitly -- beta3 and beta4,
# both industries -- but never actually applied a multiple-testing
# correction across those 4 primary tests. This does, using the
# full-20-state-treated-sample specification (the headline spec; the
# >=$0.50 subsample is a robustness cut on the same hypotheses, not a
# separate confirmatory test, so it's excluded from the correction to
# avoid double-counting).

library(dplyr)

#' Holm-adjusted p-values for the 4 primary confirmatory tests (beta3 and
#' beta4, food service and retail) at the headline specification.
holm_adjust_confirmatory <- function(mac, sample_label = "full 20-state treated sample") {
  primary <- mac %>% filter(sample == sample_label)

  raw <- dplyr::bind_rows(
    primary %>% transmute(coefficient = "beta3", industry, p_raw = model_a_p),
    primary %>% transmute(coefficient = "beta4", industry, p_raw = model_c_beta4_p)
  )
  raw$p_holm <- p.adjust(raw$p_raw, method = "holm")
  raw
}

if (sys.nframe() == 0) {
  mac <- readr::read_csv("data/processed/model_a_c_results.csv", show_col_types = FALSE)
  adjusted <- holm_adjust_confirmatory(mac)
  readr::write_csv(adjusted, "data/processed/multiple_testing_correction.csv")
  cat("\n=== Holm-adjusted p-values, confirmatory family (headline spec) ===\n")
  print(adjusted, width = Inf)
}
