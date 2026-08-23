# Post-build addition: a marginal-effect view of Model C, since a bare
# beta4 coefficient table doesn't make the interaction easy to read.
#
# Model C: log_employment ~ treated_post * exposure + controls | FE.
# The estimated treatment effect at a given exposure level is
#   effect(exposure) = beta3 + beta4 * exposure
# (beta3 is the treated_post main effect, beta4 the interaction). Its
# variance, by the delta method, is
#   Var(beta3) + exposure^2 * Var(beta4) + 2 * exposure * Cov(beta3, beta4)
# using the model's clustered variance-covariance matrix directly --
# no re-estimation needed, just linear algebra on the fitted model.

library(dplyr)
library(ggplot2)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

BETA3_TERM <- "treated_post"
BETA4_TERM <- "treated_post:exposure"

#' Estimated treatment effect (beta3 + beta4 * exposure) and its 95% CI
#' across a grid of exposure values, from a fitted Model C.
marginal_effect_curve <- function(model, exposure_grid) {
  b <- coef(model)
  v <- vcov(model)
  beta3 <- b[[BETA3_TERM]]
  beta4 <- b[[BETA4_TERM]]
  var3 <- v[BETA3_TERM, BETA3_TERM]
  var4 <- v[BETA4_TERM, BETA4_TERM]
  cov34 <- v[BETA3_TERM, BETA4_TERM]

  effect <- beta3 + beta4 * exposure_grid
  se <- sqrt(var3 + (exposure_grid^2) * var4 + 2 * exposure_grid * cov34)

  tibble::tibble(
    exposure = exposure_grid,
    effect = effect,
    se = se,
    ci_low = effect - 1.96 * se,
    ci_high = effect + 1.96 * se
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  curves <- list()
  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    model <- fit_model_c(panel)
    exposure_grid <- seq(min(panel$exposure), max(panel$exposure), length.out = 50)
    curves[[ind$industry]] <- marginal_effect_curve(model, exposure_grid) %>%
      mutate(industry = ind$industry)
  }

  curves_table <- dplyr::bind_rows(curves)
  readr::write_csv(curves_table, "data/processed/marginal_effects_curve.csv")

  p <- ggplot(curves_table, aes(x = exposure, y = effect, color = industry, fill = industry)) +
    geom_ribbon(aes(ymin = ci_low, ymax = ci_high), alpha = 0.15, color = NA) +
    geom_line(linewidth = 1) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
    labs(
      title = "Estimated treatment effect by pre-2021 exposure level",
      subtitle = "Model C: effect(exposure) = beta3 + beta4 x exposure, with 95% CI (delta method)",
      x = "Pre-2021 exposure share (12.5% band)",
      y = "Estimated treated_post effect on log employment",
      color = "Industry", fill = "Industry"
    ) +
    theme_minimal()

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/marginal_effects.png", p, width = 7, height = 5, dpi = 150)
  cat("Saved reports/figures/marginal_effects.png and data/processed/marginal_effects_curve.csv\n")
}
