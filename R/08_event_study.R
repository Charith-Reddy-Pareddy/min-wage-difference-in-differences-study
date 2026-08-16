# Day 7: event study / parallel-trends assessment (Sections 5, 6.4, 6.5).
#
# Section 6.5 is explicit that this comes before any DiD coefficient in
# the final write-up and is a direct limit on how much weight Model A's
# headline number can carry if pre-trends look poor -- the 2021 treatment
# window follows the COVID labor-market shock, which is a much bigger
# threat to this design than ordinary pre-trend concerns.
#
# "Extended 2015-2020 pre-period, with controls assigned the same 2021 Q1
# pseudo-treatment quarter as treated states" (Section 6.4): event time is
# defined relative to the real 2021Q1 date for every state, treated or
# not -- there's no separate "pseudo" assignment logic needed, since
# control states simply never have treated=1, so their event-time
# interaction terms are always 0 regardless of which quarter they're in.
# This reuses the same panel Model A/C already builds (R/07) -- it
# already covers the extended 2016Q1-2022Q4 window (2015 is consumed
# establishing the growth-covariate lag).

library(dplyr)
library(fixest)
library(ggplot2)

# Reuses build_panel(), yoy_log_growth(), etc. from R/07. source() needs a
# different relative path depending on whether this runs from the repo
# root (Rscript R/08_event_study.R) or gets source()-d from
# tests/testthat -- try both rather than duplicating R/07's functions.
if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../../R/07_model_a_c.R")
}

#' Quarters between `quarter` and `treatment_quarter` (can be negative).
relative_quarter <- function(quarter, treatment_quarter = as.Date("2021-01-01")) {
  y <- as.integer(format(quarter, "%Y"))
  m <- as.integer(format(quarter, "%m"))
  ty <- as.integer(format(treatment_quarter, "%Y"))
  tm <- as.integer(format(treatment_quarter, "%m"))
  (y - ty) * 4L + as.integer((m - tm) / 3L)
}

build_event_study_panel <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col) {
  build_panel(fred_panel, treatment_table, exposure_table, industry, outcome_col) %>%
    mutate(rel_q = relative_quarter(quarter))
}

#' Dynamic treatment effect at every relative quarter except -1 (the
#' omitted reference, i.e. the quarter just before treatment). Control
#' states have treated == 0 throughout, so they never enter these
#' interaction terms directly -- they only inform the quarter FE.
fit_event_study <- function(panel) {
  feols(log_employment ~ i(rel_q, treated, ref = -1) + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

#' Joint test that every pre-period lead (rel_q < -1) is zero -- the
#' formal version of "do pre-trends look flat." A rejection here is a
#' direct problem for Model A's identifying assumption.
pretrend_joint_test <- function(model) {
  wald(model, keep = "^rel_q::-[0-9]+:treated$")
}

#' Tidy coefficient table (relative quarter, estimate, CI) for plotting,
#' with the omitted reference quarter (-1) added back in at zero.
event_study_coefficients <- function(model) {
  ct <- as.data.frame(summary(model)$coeftable)
  ct$term <- rownames(ct)
  ct <- ct[grepl("^rel_q::", ct$term), ]
  ct$rel_q <- as.integer(sub("^rel_q::(-?[0-9]+):treated$", "\\1", ct$term))

  result <- data.frame(
    rel_q = ct$rel_q,
    estimate = ct$Estimate,
    ci_low = ct$Estimate - 1.96 * ct$`Std. Error`,
    ci_high = ct$Estimate + 1.96 * ct$`Std. Error`
  )
  rbind(result, data.frame(rel_q = -1, estimate = 0, ci_low = 0, ci_high = 0)) %>%
    arrange(rel_q)
}

save_event_study_plot <- function(coefs, industry, out_dir) {
  p <- ggplot(coefs, aes(x = rel_q, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "firebrick") +
    geom_pointrange(aes(ymin = ci_low, ymax = ci_high)) +
    labs(
      x = "Quarters relative to treatment (2021 Q1)",
      y = "Estimated effect on log employment",
      title = paste("Event study:", industry),
      subtitle = "Reference quarter: -1 (the quarter just before treatment)"
    ) +
    theme_minimal()
  ggsave(file.path(out_dir, paste0("event_study_", industry, ".png")), p, width = 8, height = 5)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  out_dir <- "reports/figures"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  pretrend_summary <- list()

  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Event study --", ind$industry, "\n")

    panel <- build_event_study_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    model <- fit_event_study(panel)

    cat("\n--- Full event-study coefficients ---\n")
    print(summary(model))

    cat("\n--- Joint test: are all pre-period leads (rel_q < -1) zero? ---\n")
    test_result <- pretrend_joint_test(model)
    print(test_result)

    coefs <- event_study_coefficients(model)
    readr::write_csv(coefs, paste0("data/processed/event_study_", ind$industry, ".csv"))
    save_event_study_plot(coefs, ind$industry, out_dir)

    pretrend_summary[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      pretrend_f_stat = test_result$stat,
      pretrend_p_value = test_result$p
    )
  }

  pretrend_table <- dplyr::bind_rows(pretrend_summary)
  readr::write_csv(pretrend_table, "data/processed/pretrend_joint_test.csv")
  cat("\n\n=== Pre-trend joint test summary ===\n")
  print(pretrend_table)
}
