# Post-build addition: is Model C's beta4 sensitive to the arbitrary
# choice of exposure bandwidth? R/04 already computes three bandwidths
# (10%, 12.5%, 15% of the pre-2021 minimum wage) but only 12.5% was ever
# used downstream. This refits Model C with all three, side by side.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

BETA4_TERM <- "treated_post:exposure"
BANDWIDTHS <- c("10%" = "exposure_share_10", "12.5%" = "exposure_share_125", "15%" = "exposure_share_15")

#' Model C's beta4 (with SE and p-value) across a set of exposure
#' bandwidth columns, for one industry's panel inputs.
bandwidth_sensitivity <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col,
                                   bandwidths = BANDWIDTHS) {
  rows <- lapply(names(bandwidths), function(label) {
    panel <- build_panel(fred_panel, treatment_table, exposure_table, industry, outcome_col,
                          exposure_band_col = bandwidths[[label]])
    ct <- fixest::coeftable(fit_model_c(panel))
    tibble::tibble(
      bandwidth = label,
      industry = industry,
      beta4 = ct[BETA4_TERM, "Estimate"],
      beta4_se = ct[BETA4_TERM, "Std. Error"],
      beta4_p = ct[BETA4_TERM, "Pr(>|t|)"]
    )
  })
  dplyr::bind_rows(rows)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  results <- dplyr::bind_rows(
    bandwidth_sensitivity(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service"),
    bandwidth_sensitivity(fred_panel, treatment_table, exposure_table, "retail", "employment_retail")
  )

  readr::write_csv(results, "data/processed/exposure_bandwidth_sensitivity.csv")
  cat("\n=== Model C beta4 across exposure bandwidths ===\n")
  print(results, width = Inf)
}
