# Day 9: Monte Carlo permutation test (Section 10), scoped to Model A only.
#
# "Treatment labels are randomly reassigned across states 10,000 times
# under a sharp null, the Model A statistic is re-estimated each time,
# and the observed estimate is compared against the empirical null
# distribution... States chose whether and when to raise wages, so this
# doesn't randomize the underlying policy assignment; it's an additional
# reference distribution rather than evidence of a randomized experiment."
#
# Reassignment happens at the state level, not the row level (each state
# has 28 quarters in the panel; a row-level shuffle would break the panel
# structure and answer a different, wrong question). Sample size
# (n_treated) is held fixed at whatever the real assignment used, since
# that's a feature of the actual design, not something the null should
# vary. Only treated_post is rebuilt each replication -- gdp_growth,
# pop_growth, and the outcome itself don't depend on treatment
# assignment, so touching them would be wasted work, not more correct.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../../R/07_model_a_c.R")
}

permutation_test_model_a <- function(panel, n_reps = 10000, seed = 1) {
  set.seed(seed)
  states <- unique(panel$state)
  n_treated <- n_distinct(panel$state[panel$treated == 1])

  observed_model <- fit_model_a(panel)
  observed_stat <- unname(coef(observed_model)["treated_post"])

  null_stats <- numeric(n_reps)
  panel_perm <- panel
  for (i in seq_len(n_reps)) {
    treated_states <- sample(states, n_treated)
    new_treated <- as.integer(panel$state %in% treated_states)
    panel_perm$treated_post <- new_treated * panel$post
    fit <- fit_model_a(panel_perm)
    null_stats[i] <- unname(coef(fit)["treated_post"])
  }

  p_value <- mean(abs(null_stats) >= abs(observed_stat))

  list(
    observed_stat = observed_stat,
    null_stats = null_stats,
    p_value = p_value,
    null_mean = mean(null_stats),
    null_sd = sd(null_stats)
  )
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
    cat("Monte Carlo permutation test, Model A --", ind$industry, "\n")

    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    t0 <- Sys.time()
    perm <- permutation_test_model_a(panel, n_reps = 10000, seed = 1)
    elapsed <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)

    cat("Observed treated_post:", round(perm$observed_stat, 5), "\n")
    cat("Null distribution: mean =", round(perm$null_mean, 5), " sd =", round(perm$null_sd, 5), "\n")
    cat("Permutation p-value:", perm$p_value, " (", 10000, "reps,", elapsed, "sec )\n")

    plot_df <- tibble::tibble(null_stat = perm$null_stats)
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = null_stat)) +
      ggplot2::geom_histogram(bins = 60, fill = "grey70", color = "white") +
      ggplot2::geom_vline(xintercept = perm$observed_stat, color = "firebrick", linewidth = 1) +
      ggplot2::labs(
        x = "Model A treated_post coefficient under permuted labels",
        y = "Count",
        title = paste("Permutation null distribution:", ind$industry),
        subtitle = paste0("Observed estimate (red line): ", round(perm$observed_stat, 4),
                           ", permutation p = ", perm$p_value)
      ) +
      ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(out_dir, paste0("permutation_test_", ind$industry, ".png")), p, width = 8, height = 5)

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      observed_treated_post = perm$observed_stat,
      null_mean = perm$null_mean,
      null_sd = perm$null_sd,
      permutation_p_value = perm$p_value
    )
  }

  results_table <- bind_rows(results)
  readr::write_csv(results_table, "data/processed/permutation_test_results.csv")
  cat("\n\n=== Permutation test summary ===\n")
  print(results_table, width = Inf)
}
