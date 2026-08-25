# Post-build addition: one figure summarizing every confirmatory
# estimate (beta3 from Model A, beta4 from Model C; both industries,
# both samples) with 95% CIs, instead of the reader having to piece it
# together across separate tables in Sections 5.1/5.2.

library(dplyr)
library(ggplot2)

#' Reshape model_a_c_results.csv into one row per (coefficient, sample,
#' industry) with a 95% CI, ready to plot.
build_forest_data <- function(mac) {
  beta3 <- mac %>%
    transmute(
      coefficient = "beta3 (Model A)",
      sample, industry,
      estimate = model_a_treated_post,
      se = model_a_se
    )
  beta4 <- mac %>%
    transmute(
      coefficient = "beta4 (Model C)",
      sample, industry,
      estimate = model_c_beta4_treated_post_x_exposure,
      se = model_c_beta4_se
    )
  dplyr::bind_rows(beta3, beta4) %>%
    mutate(
      ci_low = estimate - 1.96 * se,
      ci_high = estimate + 1.96 * se,
      label = paste(industry, "--", sample)
    )
}

if (sys.nframe() == 0) {
  mac <- readr::read_csv("data/processed/model_a_c_results.csv", show_col_types = FALSE)
  forest_data <- build_forest_data(mac)
  readr::write_csv(forest_data, "data/processed/coefficient_forest_data.csv")

  p <- ggplot(forest_data, aes(x = estimate, y = label, color = industry)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = ci_low, xmax = ci_high), size = 0.5) +
    facet_wrap(~coefficient, scales = "free_x") +
    labs(
      title = "All confirmatory estimates: beta3 and beta4, both samples, both industries",
      subtitle = "95% CI. Confirmatory family per Section 8 of the report.",
      x = "Estimate", y = NULL, color = "Industry"
    ) +
    theme_minimal(base_size = 10) +
    theme(legend.position = "top")

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/coefficient_forest_plot.png", p, width = 8, height = 4.5, dpi = 150)
  cat("Saved reports/figures/coefficient_forest_plot.png\n")
}
