# Post-build addition: is Model A's estimate driven by any single treated
# state? R/12's model diagnostics already flag Vermont, New York, and
# Hawaii as high-leverage (2020 Q2-Q3 observations), but leverage alone
# doesn't say how much the *coefficient* actually moves without them.
# This refits Model A once per treated state, with that state dropped
# entirely from the panel, and reports how far treated_post moves.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

#' Refit Model A once per treated state in `treatment_table`, each time
#' with that one state removed entirely from the panel (not just
#' recoded). Returns one row per dropped state plus the coefficient's
#' 95% CI, so the spread can be compared directly to the full-sample
#' estimate.
leave_one_out <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col) {
  treated_states <- treatment_table$state[treatment_table$group == "treated"]

  rows <- lapply(treated_states, function(dropped_state) {
    reduced_table <- treatment_table %>% filter(state != dropped_state)
    reduced_fred <- fred_panel %>% filter(state != dropped_state)
    panel <- build_panel(reduced_fred, reduced_table, exposure_table, industry, outcome_col)
    ct <- fixest::coeftable(fit_model_a(panel))
    est <- ct["treated_post", "Estimate"]
    se <- ct["treated_post", "Std. Error"]
    tibble::tibble(
      dropped_state = dropped_state,
      industry = industry,
      treated_post = est,
      se = se,
      ci_low = est - 1.96 * se,
      ci_high = est + 1.96 * se
    )
  })
  dplyr::bind_rows(rows)
}

if (sys.nframe() == 0) {
  library(ggplot2)
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  full_sample <- list()
  loo <- list()
  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("Leave-one-out for Model A --", ind$industry, "\n")
    full_panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    ct_full <- fixest::coeftable(fit_model_a(full_panel))
    full_sample[[ind$industry]] <- tibble::tibble(
      industry = ind$industry, treated_post = ct_full["treated_post", "Estimate"]
    )
    loo[[ind$industry]] <- leave_one_out(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
  }

  loo_table <- dplyr::bind_rows(loo)
  full_table <- dplyr::bind_rows(full_sample)
  readr::write_csv(loo_table, "data/processed/leave_one_out_results.csv")

  cat("\n=== Leave-one-out range (min/max treated_post across drops) ===\n")
  print(loo_table %>% group_by(industry) %>%
          summarise(min_estimate = min(treated_post), max_estimate = max(treated_post)),
        width = Inf)

  p <- ggplot(loo_table, aes(x = treated_post, y = reorder(dropped_state, treated_post))) +
    geom_vline(data = full_table, aes(xintercept = treated_post), linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = ci_low, xmax = ci_high), size = 0.3) +
    facet_wrap(~industry, scales = "free_x") +
    labs(
      title = "Model A treated_post, dropping one treated state at a time",
      subtitle = "Dashed line = full-sample estimate. Each row: that state excluded entirely.",
      x = "treated_post coefficient (95% CI)", y = NULL
    ) +
    theme_minimal(base_size = 8)

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/leave_one_out.png", p, width = 8, height = 6, dpi = 150)
  cat("Saved reports/figures/leave_one_out.png\n")
}
