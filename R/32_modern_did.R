# Modern DiD check for Model C's continuous-treatment assumption. See
# reports/final_report.Rmd's Related Literature section and README's
# Roadmap for the motivating concern: Callaway, Goodman-Bacon, and
# Sant'Anna's continuous-treatment DiD work shows that a linear TWFE
# interaction with a continuous treatment intensity can be a biased,
# hard-to-interpret weighted average when the true effect isn't linear
# in the dose -- the continuous-treatment analogue of the well-known
# staggered-binary-adoption negative-weighting problem (Goodman-Bacon
# 2021; de Chaisemartin and D'Haultfœuille 2020).
#
# Callaway-Sant'Anna (2021) and Sun-Abraham (2021) specifically target
# staggered *binary* adoption and don't mechanically apply to either of
# this study's models -- Model A has one common treatment date, and
# Model C's treatment (exposure) is continuous, not staggered timing --
# so this script does not fit either estimator. Instead it checks the
# concern those papers motivate directly: does Model C's assumed LINEAR
# interaction match what a flexible, binned dose-response actually
# looks like in this data?
#
# Two checks, both built on fixest (no new estimator package needed):
#   1. A binned dose-response: exposure cut into terciles, treated_post
#      interacted with tercile dummies instead of the raw continuous
#      exposure value. If the tercile coefficients increase roughly
#      linearly, Model C's linear interaction isn't hiding much; if they
#      don't, the linear interaction is averaging over a nonlinear
#      pattern the way the modern literature warns about.
#   2. A clean high-vs-low comparison: treated_post estimated on ONLY
#      the top and bottom exposure terciles (middle dropped), avoiding
#      any comparison between two different intermediate exposure
#      levels -- closer in spirit to Callaway-Goodman-Bacon-Sant'Anna's
#      insistence on comparisons between meaningfully different doses
#      rather than a linear functional form imposed uniformly.

library(dplyr)
library(fixest)

#' Adds an `exposure_tercile` factor (low/mid/high, by within-sample
#' cutpoints) to a Model-C-style panel. "mid" is the reference level, not
#' "low": in this data, zero treated states fall in the bottom exposure
#' tercile for either industry (see count_treated_states_per_tercile), so
#' a "low"-baseline parameterization would make treated_post itself an
#' unidentified low-tercile effect. "mid" has real treated and control
#' representation, so both interaction contrasts it anchors are
#' meaningful (see summary() output for a term that ends up unidentified
#' anyway and gets dropped for collinearity -- it will be the "low"
#' contrast, expectedly).
add_exposure_tercile <- function(panel) {
  cuts <- quantile(panel$exposure, probs = c(1 / 3, 2 / 3), na.rm = TRUE)
  panel %>%
    mutate(exposure_tercile = relevel(
      factor(
        case_when(
          exposure <= cuts[1] ~ "low",
          exposure <= cuts[2] ~ "mid",
          TRUE ~ "high"
        ),
        levels = c("low", "mid", "high")
      ),
      ref = "mid"
    ))
}

#' How many treated vs. control STATES (not state-quarters) fall in each
#' exposure tercile -- the common-support check that explains why a
#' given interaction term in fit_binned_dose_response may come back
#' unidentified: a tercile with zero treated (or zero control) states
#' can't identify a treated_post effect specific to it.
count_treated_states_per_tercile <- function(panel) {
  add_exposure_tercile(panel) %>%
    distinct(state, treated, exposure_tercile) %>%
    count(treated, exposure_tercile, name = "n_states")
}

#' Flexible dose-response: treated_post x exposure_tercile dummies
#' instead of Model C's continuous interaction.
fit_binned_dose_response <- function(panel) {
  panel <- add_exposure_tercile(panel)
  feols(log_employment ~ treated_post * exposure_tercile + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

#' Clean high-vs-low comparison: drops the middle tercile entirely, so
#' treated_post is estimated only between the two most different
#' exposure groups, rather than pooling in a linear functional form
#' across all three.
fit_high_vs_low <- function(panel) {
  panel <- add_exposure_tercile(panel) %>% filter(exposure_tercile != "mid")
  feols(log_employment ~ treated_post + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

#' Reads one coefficient out of a fixest coeftable, or NA_real_ if fixest
#' dropped that term for collinearity (which happens here exactly when a
#' tercile has no treated states to identify a treated_post effect from
#' -- an unidentified term, not a bug, so this reports NA rather than
#' erroring on the missing row).
coef_or_na <- function(coeftable, term) {
  if (term %in% rownames(coeftable)) coeftable[term, "Estimate"] else NA_real_
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  source("R/07_model_a_c.R")

  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  results <- list()

  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)

    cat("\n============================================================\n")
    cat(ind$industry, "\n")

    cat("\n--- Model C (linear treated_post*exposure, from R/07) ---\n")
    model_c <- fit_model_c(panel)
    beta4 <- summary(model_c)$coeftable["treated_post:exposure", ]
    cat("beta4 =", round(beta4["Estimate"], 5), " SE =", round(beta4["Std. Error"], 5), "\n")

    cat("\n--- Common support: treated/control STATES per exposure tercile ---\n")
    print(count_treated_states_per_tercile(panel))

    cat("\n--- Binned dose-response (treated_post x exposure tercile, mid = reference) ---\n")
    model_binned <- fit_binned_dose_response(panel)
    print(summary(model_binned))

    cat("\n--- Clean high-vs-low comparison (middle tercile dropped) ---\n")
    model_high_low <- fit_high_vs_low(panel)
    high_low <- summary(model_high_low)$coeftable["treated_post", ]
    cat("treated_post =", round(high_low["Estimate"], 5), " SE =", round(high_low["Std. Error"], 5), "\n")

    ct_binned <- summary(model_binned)$coeftable

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      model_c_beta4 = beta4["Estimate"],
      model_c_beta4_se = beta4["Std. Error"],
      binned_mid_baseline = coef_or_na(ct_binned, "treated_post"),
      binned_low_vs_mid = coef_or_na(ct_binned, "treated_post:exposure_tercilelow"),
      binned_high_vs_mid = coef_or_na(ct_binned, "treated_post:exposure_tercilehigh"),
      high_vs_low_treated_post = high_low["Estimate"],
      high_vs_low_se = high_low["Std. Error"]
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/modern_did_results.csv")
  cat("\n\n=== Summary: does the binned dose-response agree with Model C's linear interaction? ===\n")
  print(results_table, width = Inf)
}
