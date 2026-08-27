# Post-build addition: Section 8.1 established that four independent
# checks all find high- and low-exposure states differing systematically
# before the 2021 policy, but none of them explain *why*. Section 4.3
# separately established that states recovered from COVID very
# differently, and that difference confounds Model A's average effect.
# This checks the obvious candidate mechanism tying the two findings
# together: does pre-2021 exposure itself correlate with COVID severity?
# If states with more low-wage-intensive industries also happened to be
# hit harder (or recovered differently) from COVID, that single
# mechanism would explain the placebo/permutation/event-study pattern
# directly, rather than leaving it as an unexplained association.

library(dplyr)
library(ggplot2)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
  source("R/09_covid_sensitivity.R")
} else {
  source("../R/07_model_a_c.R")
  source("../R/09_covid_sensitivity.R")
}

#' Pearson correlation (and its p-value) between each state's pre-2021
#' exposure share and its COVID severity, restricted to the same
#' treated+control sample every confirmatory model uses (matching
#' build_panel's own `group != "excluded"` filter).
exposure_covid_correlation <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col,
                                        exposure_band_col = "exposure_share_125") {
  covid_severity <- compute_covid_severity(fred_panel, outcome_col)
  exposure_col <- exposure_table %>%
    filter(industry == !!industry) %>%
    select(state, exposure = all_of(exposure_band_col))

  joined <- treatment_table %>%
    filter(group != "excluded") %>%
    select(state) %>%
    inner_join(exposure_col, by = "state") %>%
    inner_join(covid_severity, by = "state") %>%
    filter(!is.na(exposure), !is.na(covid_severity))

  test <- cor.test(joined$exposure, joined$covid_severity)

  list(
    data = joined,
    correlation = unname(test$estimate),
    p_value = test$p.value,
    n = nrow(joined)
  )
}

save_correlation_plot <- function(result, industry, out_dir) {
  p <- ggplot(result$data, aes(x = exposure, y = covid_severity)) +
    geom_point(size = 2) +
    geom_smooth(method = "lm", formula = y ~ x, se = TRUE, color = "firebrick") +
    labs(
      x = "Pre-2021 exposure share (12.5% band)",
      y = "COVID severity (log employment, 2020 Q2 trough vs. 2019 Q4)",
      title = paste("Exposure vs. COVID severity:", industry),
      subtitle = paste0("r = ", round(result$correlation, 3), ", p = ", signif(result$p_value, 3),
                         ", n = ", result$n, " states")
    ) +
    theme_minimal()
  ggsave(file.path(out_dir, paste0("exposure_covid_correlation_", industry, ".png")), p, width = 7, height = 5)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  out_dir <- "reports/figures"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  results <- list()
  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Exposure vs. COVID severity correlation --", ind$industry, "\n")

    result <- exposure_covid_correlation(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    cat("r =", round(result$correlation, 4), " p =", result$p_value, " n =", result$n, "\n")
    save_correlation_plot(result, ind$industry, out_dir)

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      correlation = result$correlation,
      p_value = result$p_value,
      n_states = result$n
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/exposure_covid_correlation.csv")
  cat("\n\n=== Exposure vs. COVID severity correlation summary ===\n")
  print(results_table, width = Inf)
}
