# Day 4: Simple linear regression (Section 7) and multiple regression
# (Section 6.1), both estimated on the derived quantity from Section 4.1 --
# each state's average log change in employment, comparing a pre-period
# (2019-2020) to a post-period (2021-2022), computed separately for food
# service and retail since "food service and retail stay separate outcomes
# throughout" (Section 4.1).
#
# This isn't the study's identification strategy -- that's Model A/C
# (Day 5) plus the event study (Day 7). SLR and MLR here are the STAT
# 240/340 coursework-closure pieces (Section 9): a simple pre/post
# comparison against the dollar size of the increase, and a slightly
# richer cross-sectional regression with covariates. Neither has fixed
# effects or a proper control group in the DiD sense.

library(dplyr)
library(ggplot2)

CENSUS_REGION <- c(
  Connecticut = "Northeast", Maine = "Northeast", Massachusetts = "Northeast",
  "New Jersey" = "Northeast", "New York" = "Northeast", Vermont = "Northeast",
  Illinois = "Midwest", Michigan = "Midwest", Minnesota = "Midwest",
  Missouri = "Midwest", Ohio = "Midwest", "South Dakota" = "Midwest",
  Arkansas = "South", Maryland = "South", Florida = "South", Virginia = "South",
  Alaska = "West", Arizona = "West", California = "West", Colorado = "West",
  Montana = "West", "New Mexico" = "West", Washington = "West", Nevada = "West",
  Oregon = "West"
)

census_region <- function(state) {
  region <- CENSUS_REGION[state]
  if (any(is.na(region))) stop("No Census region for: ", paste(state[is.na(region)], collapse = ", "))
  unname(region)
}

#' Mean(log(value)) over the post window minus mean(log(value)) over the
#' pre window, for one state's time series. Vectors, not a data frame, so
#' it's trivial to test without building a full panel.
period_log_change <- function(value, quarter, pre_start, pre_end, post_start, post_end) {
  pre <- value[quarter >= pre_start & quarter <= pre_end]
  post <- value[quarter >= post_start & quarter <= post_end]
  if (length(pre) == 0 || length(post) == 0) {
    stop("Empty pre or post window -- check quarter range against the data")
  }
  mean(log(post)) - mean(log(pre))
}

PRE_START <- as.Date("2019-01-01")
PRE_END <- as.Date("2020-10-01")
POST_START <- as.Date("2021-01-01")
POST_END <- as.Date("2022-10-01")

#' One row per state: log change in food-service employment, retail
#' employment, GDP, and population, from the FRED panel, joined to
#' treatment status, the dollar increase, and Census region.
build_state_level_data <- function(fred_panel, treatment_table) {
  changes <- fred_panel %>%
    group_by(state) %>%
    summarise(
      log_change_food_service = period_log_change(
        employment_food_service, quarter, PRE_START, PRE_END, POST_START, POST_END
      ),
      log_change_retail = period_log_change(
        employment_retail, quarter, PRE_START, PRE_END, POST_START, POST_END
      ),
      gdp_growth = period_log_change(gdp, quarter, PRE_START, PRE_END, POST_START, POST_END),
      pop_growth = period_log_change(population, quarter, PRE_START, PRE_END, POST_START, POST_END),
      .groups = "drop"
    )

  changes %>%
    inner_join(treatment_table %>% select(state, group, increase), by = "state") %>%
    mutate(
      treated = as.integer(group == "treated"),
      region = census_region(state)
    )
}

#' SLR (Section 7): among treated states only, log employment change on
#' the dollar size of the wage increase.
fit_slr <- function(state_level, outcome) {
  treated <- state_level %>% filter(treated == 1)
  formula <- as.formula(paste(outcome, "~ increase"))
  lm(formula, data = treated)
}

#' MLR (Section 6.1): all states, log employment change on treatment
#' status, GDP growth, population growth, and region.
fit_mlr <- function(state_level, outcome) {
  formula <- as.formula(paste(outcome, "~ treated + gdp_growth + pop_growth + region"))
  lm(formula, data = state_level)
}

save_slr_plots <- function(model, state_level, outcome, out_dir) {
  treated <- state_level %>% filter(treated == 1)
  pred <- predict(model, newdata = treated, interval = "confidence")
  plot_df <- bind_cols(treated, as.data.frame(pred))

  scatter <- ggplot(plot_df, aes(x = increase, y = .data[[outcome]])) +
    geom_point() +
    geom_line(aes(y = fit), color = "steelblue") +
    geom_ribbon(aes(ymin = lwr, ymax = upr), alpha = 0.15, fill = "steelblue") +
    labs(
      x = "Minimum-wage increase ($)", y = paste("Log change,", outcome),
      title = paste("SLR:", outcome, "vs. wage increase (treated states)")
    ) +
    theme_minimal()
  ggsave(file.path(out_dir, paste0("slr_", outcome, "_scatter.png")), scatter, width = 6, height = 4.5)

  resid_df <- data.frame(fitted = fitted(model), residuals = resid(model))
  resid_plot <- ggplot(resid_df, aes(x = fitted, y = residuals)) +
    geom_point() +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    labs(x = "Fitted values", y = "Residuals", title = paste("SLR residuals vs. fitted:", outcome)) +
    theme_minimal()
  ggsave(file.path(out_dir, paste0("slr_", outcome, "_residuals.png")), resid_plot, width = 6, height = 4.5)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)

  state_level <- build_state_level_data(fred_panel, treatment_table)
  readr::write_csv(state_level, "data/processed/state_level_slr_mlr.csv")

  out_dir <- "reports/figures"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  for (outcome in c("log_change_food_service", "log_change_retail")) {
    cat("\n=== SLR:", outcome, "~ increase (treated states) ===\n")
    slr <- fit_slr(state_level, outcome)
    print(summary(slr))
    cat("95% CI:\n")
    print(confint(slr))
    save_slr_plots(slr, state_level, outcome, out_dir)

    cat("\n=== MLR:", outcome, "~ treated + gdp_growth + pop_growth + region (all 25 states) ===\n")
    mlr <- fit_mlr(state_level, outcome)
    print(summary(mlr))
  }
}
