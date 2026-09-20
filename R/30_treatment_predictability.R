# Post-build addition: an exploratory look at systematic pre-treatment
# differences between treated and comparison states, via two questions:
#   1. Chi-square test of independence: is treatment status independent
#      of Census region? (treated/control only -- "excluded" states
#      aren't part of the binary treated/control comparison anywhere
#      else in this project either, per R/07's own restriction.)
#   2. Logistic regression: how well can pre-period (2019-2020) GDP/
#      population growth and food-service exposure predict which states
#      got treated? Reported honestly at n=45 states -- a classifier at
#      this sample size will have real variance, not a polished result.
#
# IMPORTANT interpretive caveat: DiD does not require random treatment
# assignment. A highly predictable treatment (states raising their
# minimum wage for identifiable political/economic reasons) is entirely
# compatible with valid causal identification, provided the relevant
# conditional parallel-trends assumption holds. What a strong result here
# actually motivates is taking that parallel-trends check (R/08's event
# study) seriously, not treating predictability itself as evidence
# against the design -- see README.md's "Treatment Assignment" section
# for the full interpretation.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
  source("R/06_slr_mlr.R")
} else {
  source("../R/07_model_a_c.R")
  source("../R/06_slr_mlr.R")
}

#' Chi-square test of independence between treatment status and Census
#' region. Returns both the contingency table and the htest object.
region_treatment_chisq <- function(treatment_table) {
  df <- treatment_table %>%
    filter(group %in% c("treated", "control")) %>%
    mutate(region = census_region(state))
  tbl <- table(region = df$region, group = df$group)
  list(table = tbl, test = suppressWarnings(chisq.test(tbl)))
}

#' Average pre-period (2019-2020) year-over-year growth per state, for
#' GDP and population -- the same yoy_log_growth() used throughout R/07,
#' averaged down to one number per state since treatment (unlike
#' employment) is a state-level, not state-quarter-level, attribute.
pre_period_growth <- function(fred_panel, pre_start = as.Date("2019-01-01"), pre_end = as.Date("2020-10-01")) {
  fred_panel %>%
    group_by(state) %>%
    arrange(quarter, .by_group = TRUE) %>%
    mutate(gdp_growth = yoy_log_growth(gdp, quarter), pop_growth = yoy_log_growth(population, quarter)) %>%
    ungroup() %>%
    filter(quarter >= pre_start, quarter <= pre_end, !is.na(gdp_growth)) %>%
    group_by(state) %>%
    summarise(avg_gdp_growth = mean(gdp_growth), avg_pop_growth = mean(pop_growth), .groups = "drop")
}

#' One row per treated/control state: pre-period growth + food-service
#' exposure (12.5% band) + the binary outcome (treated).
build_predictability_data <- function(fred_panel, treatment_table, exposure_table) {
  growth <- pre_period_growth(fred_panel)
  exposure <- exposure_table %>%
    filter(industry == "food_service") %>%
    select(state, exposure = exposure_share_125)

  treatment_table %>%
    filter(group %in% c("treated", "control")) %>%
    mutate(treated = as.integer(group == "treated")) %>%
    inner_join(growth, by = "state") %>%
    inner_join(exposure, by = "state")
}

fit_treatment_classifier <- function(data) {
  glm(treated ~ avg_gdp_growth + avg_pop_growth + exposure, data = data, family = binomial)
}

#' Confusion matrix + accuracy at a given probability threshold.
classification_accuracy <- function(actual, predicted_prob, threshold = 0.5) {
  predicted <- as.integer(predicted_prob >= threshold)
  tbl <- table(actual = actual, predicted = predicted)
  list(confusion = tbl, accuracy = sum(diag(tbl)) / sum(tbl))
}

#' AUC via the Mann-Whitney U statistic: the probability a randomly
#' chosen treated state gets a higher predicted probability than a
#' randomly chosen control state -- computed directly from rank sums
#' (equivalent to the area under the ROC curve, without tracing it out
#' threshold by threshold).
auc_mann_whitney <- function(actual, predicted_prob) {
  ranks <- rank(predicted_prob)
  n1 <- sum(actual == 1)
  n0 <- sum(actual == 0)
  (sum(ranks[actual == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  chisq_result <- region_treatment_chisq(treatment_table)
  cat("=== Chi-square test: treatment status vs. Census region ===\n")
  print(chisq_result$table)
  print(chisq_result$test)

  data <- build_predictability_data(fred_panel, treatment_table, exposure_table)
  model <- fit_treatment_classifier(data)
  predicted_prob <- predict(model, type = "response")
  acc <- classification_accuracy(data$treated, predicted_prob)
  auc <- auc_mann_whitney(data$treated, predicted_prob)

  cat("\n=== Logistic regression: treated ~ pre-period growth + exposure ===\n")
  print(summary(model))
  cat("\nConfusion matrix (threshold = 0.5):\n")
  print(acc$confusion)
  cat("Accuracy:", round(acc$accuracy, 3), "| AUC:", round(auc, 3), "\n")

  results <- tibble::tibble(
    n_states = nrow(data),
    chisq_statistic = unname(chisq_result$test$statistic),
    chisq_df = unname(chisq_result$test$parameter),
    chisq_p_value = chisq_result$test$p.value,
    logit_accuracy = acc$accuracy,
    logit_auc = auc
  )
  readr::write_csv(results, "data/processed/treatment_predictability_results.csv")

  coef_table <- as.data.frame(summary(model)$coefficients)
  coef_table$term <- rownames(coef_table)
  rownames(coef_table) <- NULL
  readr::write_csv(coef_table, "data/processed/treatment_predictability_coefficients.csv")

  library(ggplot2)
  plot_data <- data %>%
    mutate(
      predicted_prob = predicted_prob,
      actual = factor(treated, levels = c(0, 1), labels = c("Control", "Treated"))
    ) %>%
    arrange(predicted_prob) %>%
    mutate(state = factor(state, levels = state))

  p <- ggplot(plot_data, aes(x = predicted_prob, y = state, color = actual)) +
    geom_point(size = 2) +
    geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
    labs(
      title = "Predicted probability of treatment, by state",
      subtitle = paste0(
        "Logistic regression on pre-period growth + exposure -- accuracy ",
        round(acc$accuracy, 2), ", AUC ", round(auc, 2)
      ),
      x = "Predicted P(treated)", y = NULL, color = NULL
    ) +
    theme_minimal(base_size = 9)

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/treatment_predictability.png", p, width = 7, height = 9, dpi = 150)
  cat("Saved reports/figures/treatment_predictability.png\n")
}
