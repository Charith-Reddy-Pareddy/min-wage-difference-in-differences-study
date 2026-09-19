# Post-build addition: ML extension. A predictive comparison, not a
# causal claim -- the study's causal estimates remain Model A/C (R/07)
# and their robustness checks (R/08-R/26). This asks a narrower,
# different question: how well can flexible ML methods predict quarterly
# employment from the same features those causal models use, versus a
# plain linear specification? It's a methods comparison on predictive
# accuracy, never a substitute for the identification strategy above.
#
# Held-out evaluation splits by STATE, not by row: a row-level random
# split would put the same state's quarters on both sides, leaking
# within-state structure (autocorrelated employment, state-level levels)
# the model could exploit -- accuracy would look better than it would on
# a genuinely unseen state. Splitting by state is the same clustering
# logic the causal models' clustered SEs already use (R/07, R/11), so the
# linear baseline here also drops the state fixed effect from R/07's
# Model A -- a state FE can't generate a prediction for a state it never
# saw, so it would be an unfair (and impossible) comparison.

library(dplyr)
library(rpart)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
  source("R/06_slr_mlr.R")
} else {
  source("../R/07_model_a_c.R")
  source("../R/06_slr_mlr.R")
}

#' Attaches each row's own year-over-year employment growth (same
#' yoy_log_growth() used for gdp_growth/pop_growth in R/07), computed
#' from the raw outcome column rather than derived from log_employment
#' level -- the prediction target below is growth, not level (see
#' build_ml_panel).
attach_employment_growth <- function(panel, fred_panel, outcome_col) {
  growth <- fred_panel %>%
    group_by(state) %>%
    arrange(quarter, .by_group = TRUE) %>%
    mutate(employment_growth = yoy_log_growth(.data[[outcome_col]], quarter)) %>%
    ungroup() %>%
    select(state, quarter, employment_growth)
  panel %>% left_join(growth, by = c("state", "quarter"))
}

#' Combined food-service + retail feature panel, with Census region
#' attached. Shared by every ML/NN script (R/27, R/28) and exported to
#' CSV below for the Python subproject (python/) -- one feature-building
#' path instead of three separately-maintained ones.
#'
#' Predicts employment_growth (year-over-year log growth), not
#' log_employment's level: the level is dominated by each state's sheer
#' size (California vs. Wyoming), which nothing in the feature set
#' (treated_post, growth covariates, exposure, region) can capture for a
#' held-out state -- that would make the state-level split above
#' unwinnable by construction. Growth is scale-invariant across states
#' and is the quantity the policy could plausibly move.
build_ml_panel <- function(fred_panel, treatment_table, exposure_table) {
  bind_rows(
    build_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service") %>%
      attach_employment_growth(fred_panel, "employment_food_service") %>%
      mutate(industry = "food_service"),
    build_panel(fred_panel, treatment_table, exposure_table, "retail", "employment_retail") %>%
      attach_employment_growth(fred_panel, "employment_retail") %>%
      mutate(industry = "retail")
  ) %>%
    mutate(region = census_region(state)) %>%
    filter(!is.na(employment_growth))
}

#' Train/test split at the state level: every quarter for a given state
#' stays on one side of the split (see file header for why row-level
#' splitting would leak). Returns the two subsetted data frames.
split_by_state <- function(panel, test_frac = 0.2, seed = 1) {
  states <- sort(unique(panel$state))
  set.seed(seed)
  test_states <- sample(states, size = max(1, round(length(states) * test_frac)))
  list(
    train = panel %>% filter(!state %in% test_states),
    test = panel %>% filter(state %in% test_states)
  )
}

rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2))

r_squared <- function(actual, predicted) {
  1 - sum((actual - predicted)^2) / sum((actual - mean(actual))^2)
}

#' Linear baseline for the predictive comparison: no state/quarter fixed
#' effects (see file header), so it can generate a prediction for a
#' held-out state at all.
fit_linear_baseline <- function(train) {
  lm(employment_growth ~ treated_post + gdp_growth + pop_growth + exposure + region, data = train)
}

#' Bootstrap-aggregated ("bagged") decision trees -- a random forest
#' assembled by hand from rpart trees rather than a randomForest-package
#' call, so the ensembling mechanics (bootstrap resampling, a random
#' feature subset per tree, averaging predictions across trees) are
#' visible rather than a library internal. `mtry` below `length(predictors)`
#' is what turns plain bagging into a random forest.
fit_bagged_trees <- function(train, predictors, response, n_trees = 25, mtry = NULL, seed = 1) {
  set.seed(seed)
  trees <- lapply(seq_len(n_trees), function(i) {
    boot_idx <- sample(nrow(train), nrow(train), replace = TRUE)
    boot_sample <- train[boot_idx, ]
    vars <- if (is.null(mtry)) predictors else sample(predictors, mtry)
    tree_formula <- reformulate(vars, response = response)
    rpart::rpart(tree_formula, data = boot_sample, control = rpart::rpart.control(cp = 0.01))
  })
  structure(list(trees = trees), class = "bagged_trees")
}

predict.bagged_trees <- function(object, newdata, ...) {
  preds <- vapply(object$trees, function(tree) predict(tree, newdata), numeric(nrow(newdata)))
  if (is.null(dim(preds))) preds <- matrix(preds, nrow = 1)
  rowMeans(preds)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  ml_panel <- build_ml_panel(fred_panel, treatment_table, exposure_table)
  readr::write_csv(ml_panel, "data/processed/ml_panel.csv")
  cat("Wrote data/processed/ml_panel.csv (", nrow(ml_panel), "rows) -- shared by R/28 and python/\n")

  split <- split_by_state(ml_panel, test_frac = 0.2, seed = 1)
  cat("Train states:", length(unique(split$train$state)),
      "| Test states:", length(unique(split$test$state)), "\n")

  predictors <- c("treated_post", "gdp_growth", "pop_growth", "exposure", "region")

  linear_model <- fit_linear_baseline(split$train)
  linear_pred <- predict(linear_model, newdata = split$test)

  bagged_model <- fit_bagged_trees(split$train, predictors, "employment_growth", n_trees = 25, mtry = 3, seed = 1)
  bagged_pred <- predict(bagged_model, split$test)

  actual <- split$test$employment_growth
  results <- tibble::tibble(
    model = c("linear_baseline", "bagged_trees"),
    rmse = c(rmse(actual, linear_pred), rmse(actual, bagged_pred)),
    r_squared = c(r_squared(actual, linear_pred), r_squared(actual, bagged_pred))
  )
  readr::write_csv(results, "data/processed/ml_prediction_results.csv")
  cat("\n=== Held-out predictive accuracy (by state, not by row) ===\n")
  print(results, width = Inf)
}
