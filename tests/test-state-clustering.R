library(testthat)
source("../R/31_state_clustering.R")

make_three_blobs <- function(seed = 1, n_per_blob = 30) {
  set.seed(seed)
  rbind(
    cbind(rnorm(n_per_blob, 0, 0.3), rnorm(n_per_blob, 0, 0.3)),
    cbind(rnorm(n_per_blob, 10, 0.3), rnorm(n_per_blob, 0, 0.3)),
    cbind(rnorm(n_per_blob, 5, 0.3), rnorm(n_per_blob, 10, 0.3))
  )
}

#' Cluster-label permutation is arbitrary (cluster "1" from one run
#' isn't necessarily cluster "1" from another) -- this checks that
#' every point from the same true blob got the same cluster label, and
#' different blobs got different labels, without caring which integer
#' label each blob received.
expect_recovers_blob_structure <- function(assignments, true_blob, n_per_blob) {
  true_blob_labels <- rep(seq_len(3), each = n_per_blob)
  tbl <- table(true_blob_labels, assignments)
  # Each true blob's points should overwhelmingly land in one cluster.
  purity <- apply(tbl, 1, max) / rowSums(tbl)
  expect_true(all(purity > 0.9))
  # And the 3 blobs shouldn't all collapse into the same cluster.
  expect_equal(length(unique(assignments)), 3)
}

test_that("kmeans_pp_init returns k rows drawn from the data", {
  X <- make_three_blobs()
  centroids <- kmeans_pp_init(X, k = 3, seed = 1)
  expect_equal(dim(centroids), c(3, 2))
  # Every initial centroid should be an actual data point.
  for (i in 1:3) {
    expect_true(any(apply(X, 1, function(row) all(row == centroids[i, ]))))
  }
})

test_that("kmeans_fit recovers three well-separated blobs", {
  X <- make_three_blobs()
  result <- kmeans_fit(X, k = 3, seed = 1)

  expect_length(result$assignments, nrow(X))
  expect_recovers_blob_structure(result$assignments, 3, 30)
  expect_true(result$wcss > 0)
  expect_true(result$iterations <= 100)
})

test_that("kmeans_fit's WCSS for the right k is much lower than for k=1", {
  X <- make_three_blobs()
  one_cluster <- kmeans_fit(X, k = 1, seed = 1)
  three_clusters <- kmeans_fit(X, k = 3, seed = 1)
  expect_true(three_clusters$wcss < one_cluster$wcss / 10)
})

test_that("kmeans_fit with k=1 puts every point in the same cluster at the global mean", {
  X <- matrix(c(1, 2, 3, 4, 5, 6), ncol = 1)
  result <- kmeans_fit(X, k = 1, seed = 1)
  expect_true(all(result$assignments == 1))
  expect_equal(unname(result$centroids[1, 1]), mean(X))
})

test_that("compute_elbow returns one WCSS value per k, non-increasing as k grows", {
  X <- make_three_blobs()
  elbow <- compute_elbow(X, max_k = 5, seed = 1)
  expect_equal(nrow(elbow), 5)
  expect_equal(elbow$k, 1:5)
  # More clusters can only reduce (never increase) total WCSS.
  expect_true(all(diff(elbow$wcss) <= 1e-9))
})

test_that("build_clustering_data joins both industries' exposure and drops excluded states", {
  quarters <- seq(as.Date("2018-01-01"), as.Date("2021-10-01"), by = "quarter")
  quarter_index <- as.integer(factor(quarters))
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas", "Vermont"), each = length(quarters)),
    quarter = rep(quarters, times = 3),
    gdp = rep(1000 * 1.01^quarter_index, times = 3),
    population = rep(5000 * 1.001^quarter_index, times = 3)
  )
  treatment_table <- tibble::tibble(
    state = c("California", "Texas", "Vermont"),
    group = c("treated", "control", "excluded")
  )
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas", "Vermont"), each = 2),
    industry = rep(c("food_service", "retail"), times = 3),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15, 0.25, 0.35)
  )

  result <- build_clustering_data(fred_panel, treatment_table, exposure_table)

  expect_equal(nrow(result), 2) # Vermont (excluded) dropped
  expect_true(all(c("exposure_food_service", "exposure_retail") %in% names(result)))
  expect_equal(result$exposure_food_service[result$state == "California"], 0.4)
  expect_equal(result$exposure_retail[result$state == "California"], 0.3)
})
