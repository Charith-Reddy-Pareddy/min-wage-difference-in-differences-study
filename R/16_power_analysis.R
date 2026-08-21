# Post-build addition: the quantitative Monte Carlo power simulation for
# beta4 (Section 4.4 of the proposal) that TIMELINE.md and the final
# report both flagged as scoped out of the original 10-day build. This
# script fills that gap; it was not part of the original 10 days -- see
# the note added to TIMELINE.md and README.md alongside it.
#
# Question: at the sample actually collected (20 treated + 25 control
# states, quarterly 2016-2022), what's the power to detect a given true
# beta4 (the treated_post x exposure interaction), and what effect size
# is detectable at 80% power?
#
# Method: same restricted-model-plus-Rademacher-residual machinery
# R/11_cluster_bootstrap.R already uses, adapted for a power curve
# instead of a single-sample CI. For each assumed true beta4 in a grid:
#   1. Take the real panel's covariates, states, and exposure values as
#      fixed (this is a power calculation conditional on the actual
#      design, not a fully synthetic one).
#   2. Build a synthetic outcome: restricted-model fitted values, plus
#      the assumed effect on treated_post*exposure, plus residuals with
#      a random +-1 sign per state (preserves the real residual
#      variance and within-state correlation structure).
#   3. Refit Model C, record whether beta4's p-value clears 0.05.
#   4. Power at that effect size = the share of replications that do.
# The minimum detectable effect (MDE) is the smallest grid value with
# power >= 0.80.

library(dplyr)
library(ggplot2)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

BETA4_TERM <- "treated_post:exposure"

#' Simulate `reps` synthetic datasets under an assumed true beta4, refit
#' Model C each time, and return the share where the beta4 p-value < 0.05.
simulate_power_at_effect <- function(panel, true_beta4, reps = 500, seed = 1) {
  old_notes <- fixest::getFixest_notes()
  fixest::setFixest_notes(FALSE)
  on.exit(fixest::setFixest_notes(old_notes), add = TRUE)

  restricted <- fit_model_a(panel) # beta4 = 0, same reduction R/11 uses
  fitted_restricted <- fitted(restricted)
  resid_restricted <- resid(restricted)
  clusters <- panel$state
  unique_clusters <- unique(clusters)
  treated_post_x_exposure <- panel$treated_post * panel$exposure

  set.seed(seed)
  panel_sim <- panel
  significant <- logical(reps)
  for (r in seq_len(reps)) {
    weights <- stats::setNames(sample(c(-1, 1), length(unique_clusters), replace = TRUE), unique_clusters)
    panel_sim$log_employment <- fitted_restricted +
      true_beta4 * treated_post_x_exposure +
      resid_restricted * weights[clusters]
    fit_r <- fit_model_c(panel_sim)
    p_r <- fixest::coeftable(fit_r)[BETA4_TERM, "Pr(>|t|)"]
    significant[r] <- !is.na(p_r) && p_r < 0.05
  }
  mean(significant)
}

#' Minimum detectable effect: the smallest effect size whose power clears
#' `threshold`, or NA if none in the grid does. Assumes `effect_grid` is
#' sorted ascending (the caller's responsibility, not re-sorted here so a
#' mismatched effect_size/power pairing can't silently get reordered).
select_mde <- function(effect_grid, power, threshold = 0.80) {
  above <- effect_grid[power >= threshold]
  if (length(above) > 0) min(above) else NA_real_
}

#' Power curve across a grid of assumed effect sizes, plus the minimum
#' detectable effect at 80% power.
power_curve <- function(panel, effect_grid, reps = 500, seed = 1) {
  power <- vapply(
    seq_along(effect_grid),
    function(i) simulate_power_at_effect(panel, effect_grid[i], reps = reps, seed = seed + i),
    numeric(1)
  )
  list(
    table = tibble::tibble(effect_size = effect_grid, power = power),
    mde_80 = select_mde(effect_grid, power, threshold = 0.80)
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  # Section 4.4's own assumed range (0.5%-3%) was written for beta3 (Model
  # A's average effect, same units as log employment). beta4 is on a
  # different scale -- it's the coefficient on treated_post x exposure,
  # where exposure is a 0-1 share, so the observed beta4 estimates
  # (0.17 and -0.005 in the full sample; see model_a_c_results.csv) are
  # numerically much larger. Grid set to bracket the real observed
  # values and their standard errors (~0.08-0.23), not the beta3 range.
  effect_grid <- seq(0.02, 0.6, by = 0.02)

  results <- list()
  curves <- list()

  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Power simulation for beta4 --", ind$industry, "(full 20-state treated sample)\n")

    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    t0 <- Sys.time()
    curve <- power_curve(panel, effect_grid, reps = 500, seed = 1)
    elapsed <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)

    cat("MDE at 80% power:", ifelse(is.na(curve$mde_80), "not reached on this grid", round(curve$mde_80, 4)),
        " (", length(effect_grid), "grid points x 500 reps,", elapsed, "sec )\n")

    curves[[ind$industry]] <- curve$table %>% mutate(industry = ind$industry)
    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      observed_beta4 = fixest::coeftable(fit_model_c(panel))[BETA4_TERM, "Estimate"],
      mde_80 = curve$mde_80
    )
  }

  curves_table <- dplyr::bind_rows(curves)
  results_table <- dplyr::bind_rows(results)
  readr::write_csv(curves_table, "data/processed/power_analysis_curve.csv")
  readr::write_csv(results_table, "data/processed/power_analysis_results.csv")

  cat("\n\n=== Power analysis summary ===\n")
  print(results_table, width = Inf)

  p <- ggplot(curves_table, aes(x = effect_size, y = power, color = industry)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    geom_hline(yintercept = 0.80, linetype = "dashed", color = "grey40") +
    scale_x_continuous(labels = scales::label_percent(accuracy = 1)) +
    scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0, 1)) +
    labs(
      title = "Power to detect beta4 (exposure gradient), by assumed effect size",
      subtitle = "Design: 20 treated + 25 control states, quarterly 2016-2022, state-clustered residual simulation",
      x = "Assumed true beta4 (log-point exposure gradient)",
      y = "Simulated power",
      color = "Industry"
    ) +
    theme_minimal()

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/power_analysis.png", p, width = 7, height = 5, dpi = 150)
  cat("Saved reports/figures/power_analysis.png\n")
}
