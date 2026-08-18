# Day 8: wild cluster bootstrap CI for beta4 (Section 8).
#
# fwildclusterboot -- the standard package for this -- was pulled from
# CRAN in May 2024 (archived, not building against current R). Rather
# than depend on an unmaintained GitHub install, this implements the
# Cameron-Gelbach-Miller wild cluster bootstrap directly: it's a fully
# specified, well-documented algorithm, and with only ~45 clusters and a
# fast fixest fit, it's cheap enough to just do.
#
# NOTE ON THE PROPOSAL'S OWN WORDING: Section 8 says "states get
# resampled, not individual state-quarter rows," which describes a
# (non-wild) pairs cluster bootstrap -- resampling clusters with
# replacement. But it also names the method "wild cluster bootstrap
# (Cameron-Gelbach-Miller-style)," which is a different, better-known
# procedure for exactly this low-cluster-count problem: it does NOT
# resample clusters at all. It keeps every cluster and instead
# randomizes the *sign* of each cluster's residuals (a fixed Rademacher
# weight per cluster, restricted-model residuals, refit, repeat). The
# named method is implemented here, since that's the specific,
# unambiguous citation and the reason wild bootstraps exist in the first
# place is that plain resampling performs poorly with this few clusters.
#
# Procedure:
#   1. Fit the restricted model (beta4 = 0). Because exposure's bare main
#      effect is already absorbed by the state FE (R/07's own
#      collinearity note), the beta4=0 restriction on Model C reduces
#      exactly to Model A's formula -- no separate restricted spec to
#      write.
#   2. For each of B replications: draw one Rademacher weight (+1/-1)
#      per state, build a synthetic outcome from the restricted model's
#      fitted values plus its residuals scaled by that state's weight,
#      refit the FULL model, record beta4's t-statistic.
#   3. Bootstrap p-value: share of |t*| at least as large as the
#      observed |t|. CI: the studentized ("bootstrap-t") interval, which
#      is the standard construction here since the reference distribution
#      being bootstrapped is the t-statistic, not the raw coefficient.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../../R/07_model_a_c.R")
}

BETA4_TERM <- "treated_post:exposure"

#' fit_model_c() correctly drops exposure's bare main effect every single
#' bootstrap replication (documented in R/07: it's collinear with the
#' state FE). fixest reports that as a note each time by default, which
#' floods B=999 replications with an identical, already-understood
#' message -- silenced here rather than actually suppressing the check.
wild_cluster_bootstrap_beta4 <- function(panel, B = 999, seed = 1) {
  old_notes <- fixest::getFixest_notes()
  fixest::setFixest_notes(FALSE)
  on.exit(fixest::setFixest_notes(old_notes), add = TRUE)

  restricted <- fit_model_a(panel) # beta4 = 0 reduces exactly to Model A
  full <- fit_model_c(panel)

  ct_full <- fixest::coeftable(full)
  observed_coef <- ct_full[BETA4_TERM, "Estimate"]
  observed_se <- ct_full[BETA4_TERM, "Std. Error"]
  observed_t <- ct_full[BETA4_TERM, "t value"]

  fitted_restricted <- fitted(restricted)
  resid_restricted <- resid(restricted)
  clusters <- panel$state
  unique_clusters <- unique(clusters)

  set.seed(seed)
  boot_t <- numeric(B)
  panel_boot <- panel
  for (b in seq_len(B)) {
    weights <- stats::setNames(sample(c(-1, 1), length(unique_clusters), replace = TRUE), unique_clusters)
    panel_boot$log_employment <- fitted_restricted + resid_restricted * weights[clusters]
    fit_b <- fit_model_c(panel_boot)
    boot_t[b] <- fixest::coeftable(fit_b)[BETA4_TERM, "t value"]
  }

  p_value <- mean(abs(boot_t) >= abs(observed_t))
  ci <- observed_coef - stats::quantile(boot_t, c(0.975, 0.025)) * observed_se

  list(
    observed_coef = unname(observed_coef),
    observed_se = unname(observed_se),
    observed_t = unname(observed_t),
    boot_t = boot_t,
    p_value = p_value,
    ci_low = unname(ci[1]),
    ci_high = unname(ci[2])
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  results <- list()

  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Wild cluster bootstrap for beta4 --", ind$industry, "(full 20-state treated sample)\n")

    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    t0 <- Sys.time()
    boot <- wild_cluster_bootstrap_beta4(panel, B = 999, seed = 1)
    elapsed <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)

    cat("beta4 (Model C, asymptotic):", round(boot$observed_coef, 4),
        " SE:", round(boot$observed_se, 4), " t:", round(boot$observed_t, 3), "\n")
    cat("Wild cluster bootstrap: p =", round(boot$p_value, 4),
        " 95% CI = [", round(boot$ci_low, 4), ",", round(boot$ci_high, 4), "]",
        " (", B <- 999, "reps,", elapsed, "sec )\n")

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      beta4 = boot$observed_coef,
      beta4_se_asymptotic = boot$observed_se,
      beta4_t_asymptotic = boot$observed_t,
      wild_boot_p_value = boot$p_value,
      wild_boot_ci_low = boot$ci_low,
      wild_boot_ci_high = boot$ci_high
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/cluster_bootstrap_results.csv")
  cat("\n\n=== Wild cluster bootstrap summary ===\n")
  print(results_table, width = Inf)
}
