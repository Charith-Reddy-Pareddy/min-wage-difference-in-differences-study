# Post-build addition: neural-network extension of the ML predictive
# comparison started in R/27 (same caveat applies -- this is a
# predictive-accuracy comparison, not a causal claim; Model A/C in R/07
# remain the study's identification strategy). Reuses R/27's shared
# ml_panel.csv and state-level train/test split so all three methods
# (linear baseline, bagged trees, neural net) are compared on the exact
# same held-out states.
#
# A single hidden-layer feedforward network (nnet::nnet) rather than a
# deep architecture: ~1,000 training rows and 5 predictors is nowhere
# near enough data to fit a deep net without it either failing to
# converge usefully or overfitting outright -- model capacity should
# match sample size, not the other way around.
#
# nnet's gradient-based fitting is sensitive to input/output scale (unlike
# the tree-based and linear methods above), so predictors and the
# response are standardized using TRAIN-set mean/SD only, then
# predictions are unstandardized back to log_employment's original
# scale -- fitting the scaler on the test set too would leak test-set
# statistics into training.

library(dplyr)
library(nnet)

if (file.exists("R/27_ml_prediction.R")) {
  source("R/27_ml_prediction.R")
} else {
  source("../R/27_ml_prediction.R")
}

standardize_by <- function(x, mean, sd) (x - mean) / sd
unstandardize_by <- function(z, mean, sd) z * sd + mean

#' Fit a single-hidden-layer feedforward network on `train`, predict on
#' `test`. Returns the fitted model, the predictions (on log_employment's
#' original scale), and the train-set scaling stats (kept for
#' reproducibility/inspection, not reused across calls).
fit_neural_network <- function(train, test, size = 5, seed = 1, maxit = 300) {
  scale_cols <- c("gdp_growth", "pop_growth", "exposure", "employment_growth")
  scale_stats <- lapply(scale_cols, function(col) {
    s <- stats::sd(train[[col]])
    list(mean = mean(train[[col]]), sd = if (s == 0) 1 else s)
  })
  names(scale_stats) <- scale_cols

  scale_frame <- function(df) {
    for (col in scale_cols) {
      df[[paste0(col, "_z")]] <- standardize_by(df[[col]], scale_stats[[col]]$mean, scale_stats[[col]]$sd)
    }
    df
  }
  train_scaled <- scale_frame(train)
  test_scaled <- scale_frame(test)

  set.seed(seed)
  fit <- nnet::nnet(
    employment_growth_z ~ treated_post + gdp_growth_z + pop_growth_z + exposure_z + region,
    data = train_scaled, size = size, linout = TRUE, trace = FALSE, maxit = maxit
  )
  pred_z <- as.numeric(predict(fit, newdata = test_scaled))
  predictions <- unstandardize_by(pred_z, scale_stats$employment_growth$mean, scale_stats$employment_growth$sd)

  list(model = fit, predictions = predictions, scale_stats = scale_stats)
}

#' Combine R/27's linear/bagged-trees results with the neural network's,
#' into the single 3-row comparison table the report/README references.
build_comparison_table <- function(prior_results, nn_rmse, nn_r_squared) {
  dplyr::bind_rows(
    prior_results,
    tibble::tibble(model = "neural_network", rmse = nn_rmse, r_squared = nn_r_squared)
  )
}

if (sys.nframe() == 0) {
  ml_panel <- readr::read_csv("data/processed/ml_panel.csv", show_col_types = FALSE)
  prior_results <- readr::read_csv("data/processed/ml_prediction_results.csv", show_col_types = FALSE)

  # Same seed as R/27 -- identical state-level split, so all three
  # models are evaluated on the same held-out states.
  split <- split_by_state(ml_panel, test_frac = 0.2, seed = 1)

  nn <- fit_neural_network(split$train, split$test, size = 5, seed = 1, maxit = 300)
  nn_rmse <- rmse(split$test$employment_growth, nn$predictions)
  nn_r_squared <- r_squared(split$test$employment_growth, nn$predictions)

  readr::write_csv(
    tibble::tibble(model = "neural_network", rmse = nn_rmse, r_squared = nn_r_squared),
    "data/processed/neural_network_results.csv"
  )

  comparison <- build_comparison_table(prior_results, nn_rmse, nn_r_squared)
  readr::write_csv(comparison, "data/processed/ml_comparison_results.csv")

  cat("\n=== Held-out predictive accuracy, all three methods (same split as R/27) ===\n")
  print(comparison, width = Inf)
}
