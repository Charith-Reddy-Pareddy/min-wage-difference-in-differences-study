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
library(randomForest)
library(gbm)

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
    # A factor, not a character column: lm()/rpart()/randomForest() all
    # coerce a character predictor to a factor internally via
    # model.frame(), but gbm()'s cross-validation workers don't.
    mutate(region = factor(census_region(state))) %>%
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

#' Bootstrap-aggregated ("bagged") decision trees, assembled by hand from
#' rpart trees rather than a library call, so the ensembling mechanics
#' (bootstrap resampling, averaging predictions across trees) are visible
#' rather than a black box. When `mtry` is set, each tree also gets a
#' fixed random subset of features for its entire fit -- the "random
#' subspace" method (Ho 1998), a cheap way to decorrelate trees without a
#' custom tree-fitting routine. This is NOT Breiman's random forest
#' algorithm: a real random forest re-samples the feature subset at
#' EVERY split node, not once per tree, so different splits within the
#' same tree can draw on different features. See fit_random_forest()
#' below for that -- rpart doesn't expose per-node feature sampling, so
#' this hand-rolled version is deliberately the simpler, different
#' method, not an approximation of it.
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

#' Breiman's random forest, via the randomForest package: bagged trees
#' where every split, in every tree, re-samples which `mtry` features are
#' even candidates for that split -- the actual algorithm fit_bagged_trees
#' above deliberately doesn't implement (rpart has no hook for per-node
#' feature sampling). `mtry` defaults to the package's own regression
#' default (floor(number of predictors / 3)).
fit_random_forest <- function(train, predictors, response, n_trees = 500, mtry = NULL, seed = 1) {
  set.seed(seed)
  formula <- reformulate(predictors, response = response)
  args <- list(formula = formula, data = train, ntree = n_trees)
  if (!is.null(mtry)) args$mtry <- mtry
  do.call(randomForest::randomForest, args)
}

#' Gradient boosting (Friedman's GBM, via the gbm package): unlike the
#' two ensembles above, trees here are fit SEQUENTIALLY, each one to the
#' current residuals of the ensemble so far, rather than independently in
#' parallel on bootstrap resamples -- a fundamentally different way of
#' combining weak learners (boosting, not bagging). Fits with a
#' generous `n_trees` ceiling and picks the actual number of trees to use
#' via 5-fold cross-validation (gbm.perf) rather than just using all of
#' them, since boosting keeps improving training fit indefinitely and
#' will overfit if the iteration count isn't chosen deliberately.
fit_gradient_boosting <- function(train, predictors, response, n_trees = 1000,
                                   interaction_depth = 3, shrinkage = 0.01, seed = 1) {
  set.seed(seed)
  formula <- reformulate(predictors, response = response)
  gbm::gbm(
    formula, data = train, distribution = "gaussian",
    n.trees = n_trees, interaction.depth = interaction_depth, shrinkage = shrinkage,
    cv.folds = 5, verbose = FALSE
  )
}

#' Predicts using the cross-validation-selected number of trees (see
#' fit_gradient_boosting) rather than the full n_trees ceiling.
predict_gradient_boosting <- function(model, newdata) {
  best_iter <- gbm::gbm.perf(model, method = "cv", plot.it = FALSE)
  predict(model, newdata = newdata, n.trees = best_iter)
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

  rf_model <- fit_random_forest(split$train, predictors, "employment_growth", n_trees = 500, seed = 1)
  rf_pred <- predict(rf_model, newdata = split$test)

  gb_model <- fit_gradient_boosting(split$train, predictors, "employment_growth", seed = 1)
  gb_pred <- predict_gradient_boosting(gb_model, split$test)

  actual <- split$test$employment_growth
  results <- tibble::tibble(
    model = c("linear_baseline", "bagged_trees", "random_forest", "gradient_boosting"),
    rmse = c(
      rmse(actual, linear_pred), rmse(actual, bagged_pred), rmse(actual, rf_pred), rmse(actual, gb_pred)
    ),
    r_squared = c(
      r_squared(actual, linear_pred), r_squared(actual, bagged_pred),
      r_squared(actual, rf_pred), r_squared(actual, gb_pred)
    )
  )
  readr::write_csv(results, "data/processed/ml_prediction_results.csv")
  cat("\n=== Held-out predictive accuracy (by state, not by row) ===\n")
  print(results, width = Inf)
}
