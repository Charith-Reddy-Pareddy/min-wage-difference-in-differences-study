# Day 8: model diagnostics (Section 11) -- linearity, normality, constant
# variance, influential observations, for Model A.
#
# Independence is already addressed by state-clustered SEs throughout
# (used in every model since R/07), so it isn't a separate plot here.
#
# Uses fit_model_a_lm_crosscheck() from R/07 rather than the fixest fit:
# it's a real lm object, and base R's plot.lm() produces exactly this
# classic 4-panel set (residuals vs. fitted, Q-Q, scale-location,
# residuals vs. leverage with Cook's distance contours) directly, well
# tested, no need to reimplement it. R/07 already cross-checked this
# lm() specification's coefficients against fixest's, so the diagnostics
# apply to the same model that's actually being interpreted.

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

save_model_a_diagnostics <- function(panel, industry, out_dir) {
  model <- fit_model_a_lm_crosscheck(panel)

  path <- file.path(out_dir, paste0("model_a_diagnostics_", industry, ".png"))
  grDevices::png(path, width = 1000, height = 1000, res = 120)
  graphics::par(mfrow = c(2, 2))
  graphics::plot(model, which = 1:4, sub.caption = paste("Model A diagnostics:", industry))
  grDevices::dev.off()

  cook_d <- stats::cooks.distance(model)
  influential_threshold <- 4 / length(cook_d) # common rule of thumb
  influential <- names(cook_d)[cook_d > influential_threshold]

  list(
    n_obs = length(cook_d),
    n_influential = length(influential),
    influential_threshold = influential_threshold,
    max_cooks_distance = max(cook_d),
    shapiro_p_value = tryCatch(
      stats::shapiro.test(stats::residuals(model))$p.value,
      error = function(e) NA_real_ # shapiro.test caps at 5000 obs; not expected to trigger here
    )
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
    cat("Model A diagnostics --", ind$industry, "\n")

    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    diag <- save_model_a_diagnostics(panel, ind$industry, out_dir)

    cat("n obs:", diag$n_obs, " influential (Cook's D >", round(diag$influential_threshold, 4), "):",
        diag$n_influential, " max Cook's D:", round(diag$max_cooks_distance, 4), "\n")
    cat("Shapiro-Wilk normality test on residuals: p =", round(diag$shapiro_p_value, 4), "\n")

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      n_obs = diag$n_obs,
      n_influential = diag$n_influential,
      max_cooks_distance = diag$max_cooks_distance,
      shapiro_p_value = diag$shapiro_p_value
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/model_diagnostics_summary.csv")
  cat("\n\n=== Model A diagnostics summary ===\n")
  print(results_table, width = Inf)
}
