# Post-build addition: a second new research angle, this one unsupervised
# rather than supervised (R/30's logistic regression, and every ML model
# in R/27-R/28, all predict a known label; nothing so far has asked
# whether states form natural groups without being told the answer).
# Hand-rolled k-means (with k-means++ initialization) rather than a
# library call, consistent with this project's standing practice for
# algorithms that don't already have a real dependency in use elsewhere
# (R/27's fit_bagged_trees(); Python's BaggedTrees/RandomForest/
# GradientBoostedTrees) -- base R's own stats::kmeans() would work fine,
# but the point here (as there) is that the mechanics are visible.
#
# Question: do states cluster into distinguishable economic profiles
# (pre-period growth + exposure), and if so, does treatment status track
# those clusters at all, or cut across them? This is exploratory, not a
# fourth confirmatory test -- no cluster-based hypothesis was
# pre-registered, so results here inform interpretation rather than
# replace Sections 4-8's confirmatory battery. Same caveat as R/30: DiD
# doesn't require random assignment, so a clean cluster/treatment split
# doesn't itself invalidate the design -- it motivates taking R/08's
# direct parallel-trends test seriously, which is where the actual
# identification verdict comes from.

library(dplyr)

if (file.exists("R/30_treatment_predictability.R")) {
  source("R/30_treatment_predictability.R")
} else {
  source("../R/30_treatment_predictability.R")
}

#' k-means++ initialization (Arthur & Vassilvitskii 2007): the first
#' centroid is a uniformly random point; each subsequent centroid is
#' sampled with probability proportional to its squared distance from
#' the nearest centroid already chosen. Spreads the initial centroids
#' out, which converges faster and more reliably than picking k
#' uniformly random starting points (which can land two centroids near
#' each other and waste iterations separating them back out).
kmeans_pp_init <- function(X, k, seed = 1) {
  X <- as.matrix(X)
  set.seed(seed)
  centroids <- X[sample(nrow(X), 1), , drop = FALSE]
  while (nrow(centroids) < k) {
    dist_sq <- apply(X, 1, function(row) min(rowSums(sweep(centroids, 2, row)^2)))
    next_idx <- sample(nrow(X), 1, prob = dist_sq / sum(dist_sq))
    centroids <- rbind(centroids, X[next_idx, ])
  }
  unname(centroids)
}

#' Lloyd's algorithm: alternate assigning each point to its nearest
#' centroid and recomputing centroids as the mean of their assigned
#' points, until assignments stop changing (or max_iter is hit). An
#' empty cluster keeps its previous centroid rather than erroring.
kmeans_fit <- function(X, k, seed = 1, max_iter = 100) {
  X <- as.matrix(X)
  centroids <- kmeans_pp_init(X, k, seed)
  assignments <- rep(NA_integer_, nrow(X))

  for (iter in seq_len(max_iter)) {
    new_assignments <- apply(X, 1, function(row) which.min(rowSums(sweep(centroids, 2, row)^2)))
    if (identical(new_assignments, assignments)) break
    assignments <- new_assignments
    centroids <- t(vapply(seq_len(k), function(j) {
      cluster_points <- X[assignments == j, , drop = FALSE]
      if (nrow(cluster_points) == 0) centroids[j, ] else colMeans(cluster_points)
    }, numeric(ncol(X))))
  }

  wcss <- sum(vapply(seq_len(k), function(j) {
    cluster_points <- X[assignments == j, , drop = FALSE]
    if (nrow(cluster_points) == 0) 0 else sum(sweep(cluster_points, 2, centroids[j, ])^2)
  }, numeric(1)))

  list(centroids = centroids, assignments = assignments, iterations = iter, wcss = wcss)
}

#' Total within-cluster sum of squares for k = 1..max_k, for an elbow
#' plot -- the standard (if informal) way to judge how many clusters the
#' data actually supports before picking one.
compute_elbow <- function(X, max_k = 8, seed = 1) {
  tibble::tibble(
    k = seq_len(max_k),
    wcss = vapply(seq_len(max_k), function(k) kmeans_fit(X, k, seed = seed)$wcss, numeric(1))
  )
}

#' One row per treated/control state: pre-period growth (R/30) plus
#' BOTH industries' exposure (R/30's predictability data only used
#' food-service exposure; clustering uses both, since it's describing
#' each state's overall economic profile, not predicting one industry's
#' treatment).
build_clustering_data <- function(fred_panel, treatment_table, exposure_table) {
  growth <- pre_period_growth(fred_panel)
  exposure_wide <- exposure_table %>%
    filter(industry %in% c("food_service", "retail")) %>%
    select(state, industry, exposure_share_125) %>%
    tidyr::pivot_wider(names_from = industry, values_from = exposure_share_125,
                        names_prefix = "exposure_")

  treatment_table %>%
    filter(group %in% c("treated", "control")) %>%
    inner_join(growth, by = "state") %>%
    inner_join(exposure_wide, by = "state")
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  data <- build_clustering_data(fred_panel, treatment_table, exposure_table)
  feature_cols <- c("avg_gdp_growth", "avg_pop_growth", "exposure_food_service", "exposure_retail")
  X_scaled <- scale(as.matrix(data[, feature_cols]))

  elbow <- compute_elbow(X_scaled, max_k = 8, seed = 1)
  readr::write_csv(elbow, "data/processed/state_clustering_elbow.csv")

  # k = 3: the elbow curve itself is gradual rather than a sharp bend at
  # any one k (see reports/figures/state_clustering_elbow.png), so this
  # is a judgment call informed by the plot, not a value the plot alone
  # dictates -- k=3 is the smallest k that separates into more than a
  # single "everyone" cluster while still leaving each cluster large
  # enough to interpret.
  k <- 3
  clusters <- kmeans_fit(X_scaled, k = k, seed = 1)
  data$cluster <- factor(clusters$assignments)

  cat("=== k-means (k =", k, ") on pre-period growth + exposure, standardized ===\n")
  cat("WCSS:", round(clusters$wcss, 2), "| iterations:", clusters$iterations, "\n\n")

  cluster_treatment_table <- table(cluster = data$cluster, group = data$group)
  cat("Cluster x treatment-status cross-tab:\n")
  print(cluster_treatment_table)
  chisq_result <- suppressWarnings(chisq.test(cluster_treatment_table))
  cat("\nChi-square test (cluster independent of treatment status?):\n")
  print(chisq_result)

  pca <- prcomp(X_scaled)
  variance_explained <- summary(pca)$importance["Proportion of Variance", 1:2]

  results <- tibble::tibble(
    k = k,
    wcss = clusters$wcss,
    chisq_statistic = unname(chisq_result$statistic),
    chisq_p_value = chisq_result$p.value,
    pc1_variance_explained = variance_explained[1],
    pc2_variance_explained = variance_explained[2]
  )
  readr::write_csv(results, "data/processed/state_clustering_results.csv")

  cluster_assignments <- data %>%
    mutate(pc1 = pca$x[, 1], pc2 = pca$x[, 2]) %>%
    select(state, group, cluster, pc1, pc2, all_of(feature_cols))
  readr::write_csv(cluster_assignments, "data/processed/state_clustering_assignments.csv")

  library(ggplot2)
  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)

  p_elbow <- ggplot(elbow, aes(x = k, y = wcss)) +
    geom_line(color = "grey50") +
    geom_point(size = 2, color = "#9a3324") +
    geom_vline(xintercept = k, linetype = "dashed", color = "grey60") +
    scale_x_continuous(breaks = elbow$k) +
    labs(title = "K-means elbow curve", subtitle = paste0("Chosen k = ", k, " (dashed line)"),
         x = "k", y = "Total within-cluster sum of squares") +
    theme_minimal()
  ggsave("reports/figures/state_clustering_elbow.png", p_elbow, width = 6, height = 4.5, dpi = 150)

  p_pca <- ggplot(cluster_assignments, aes(x = pc1, y = pc2, color = cluster, shape = group)) +
    geom_point(size = 2.5, alpha = 0.85) +
    labs(
      title = "State economic profiles: k-means clusters vs. treatment status",
      subtitle = paste0(
        "PC1 (", round(variance_explained[1] * 100), "%) x PC2 (", round(variance_explained[2] * 100),
        "%) of pre-period growth + exposure"
      ),
      x = "PC1", y = "PC2", color = "Cluster", shape = "Treatment status"
    ) +
    theme_minimal()
  ggsave("reports/figures/state_clustering_pca.png", p_pca, width = 7.5, height = 5.5, dpi = 150)

  cat("\nSaved reports/figures/state_clustering_elbow.png and state_clustering_pca.png\n")
}
