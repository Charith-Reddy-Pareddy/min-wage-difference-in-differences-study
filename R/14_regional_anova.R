# Day 9: one-way regional ANOVA (Section 6.3, exploratory).
#
# "A single one-way ANOVA test on whether regions differ in employment
# growth, alongside a descriptive boxplot by region and treatment status.
# The exposure interaction in Model C is the formal test of heterogeneity
# and is not superseded by this check -- it's included only to satisfy
# the STAT 340 ANOVA requirement in lightweight form."
#
# Reuses build_state_level_data() from R/06 (the same per-state log
# employment change, 2019-2020 pre-period vs. 2021-2022 post-period,
# with Census region already attached) rather than a third definition of
# "employment growth." Uses the full sample (treated + excluded +
# control) since this is a general regional-differences check, not a
# treatment-effect estimate -- unlike R/06's MLR and R/07's Model A/C,
# which correctly restrict to treated + control only.

library(dplyr)
library(ggplot2)

if (file.exists("R/06_slr_mlr.R")) {
  source("R/06_slr_mlr.R")
} else {
  source("../../R/06_slr_mlr.R")
}

regional_anova <- function(state_level, outcome) {
  formula <- as.formula(paste(outcome, "~ region"))
  stats::aov(formula, data = state_level)
}

save_regional_boxplot <- function(state_level, outcome, out_dir) {
  p <- ggplot(state_level, aes(x = region, y = .data[[outcome]], fill = group)) +
    geom_boxplot(outlier.shape = NA) +
    geom_jitter(width = 0.15, alpha = 0.5, size = 1) +
    labs(
      x = "Census region", y = paste("Log change,", outcome),
      title = paste("Employment change by region and treatment status:", outcome),
      fill = "Group"
    ) +
    theme_minimal()
  ggsave(file.path(out_dir, paste0("regional_boxplot_", outcome, ".png")), p, width = 8, height = 5)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)

  state_level <- build_state_level_data(fred_panel, treatment_table)

  out_dir <- "reports/figures"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  results <- list()
  for (outcome in c("log_change_food_service", "log_change_retail")) {
    cat("\n============================================================\n")
    cat("One-way ANOVA:", outcome, "~ region (all", nrow(state_level), "states)\n")

    model <- regional_anova(state_level, outcome)
    print(summary(model))
    save_regional_boxplot(state_level, outcome, out_dir)

    s <- summary(model)[[1]]
    results[[outcome]] <- tibble::tibble(
      outcome = outcome,
      f_statistic = s["region", "F value"],
      df_region = s["region", "Df"],
      df_residuals = s["Residuals", "Df"],
      p_value = s["region", "Pr(>F)"]
    )
  }

  results_table <- bind_rows(results)
  readr::write_csv(results_table, "data/processed/regional_anova_results.csv")
  cat("\n\n=== Regional ANOVA summary ===\n")
  print(results_table, width = Inf)
}
