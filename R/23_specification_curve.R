# Post-build addition: a specification curve for beta4 (Simonsohn,
# Simmons & Nelson-style multiverse analysis), varying every analytical
# choice that R/17's bandwidth check and R/07's sample cut each varied
# separately, together in one comprehensive view: exposure band (10%,
# 12.5%, 15%) x sample (full 20-state, >=$0.50 subsample) x industry
# (food service, retail) = 12 specifications, all for the same
# hypothesis test (beta4). Answers directly: out of every reasonable
# combination of choices actually used elsewhere in this report, how
# many come back significant, and does the sign depend on which corner
# of the multiverse you're in?

library(dplyr)
library(ggplot2)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

BETA4_TERM <- "treated_post:exposure"
BANDWIDTHS <- c("10%" = "exposure_share_10", "12.5%" = "exposure_share_125", "15%" = "exposure_share_15")
SAMPLES <- list(
  "full 20-state sample" = function(tt) tt,
  ">=$0.50 subsample" = function(tt) tt %>% filter(group != "treated" | increase >= 0.50)
)

#' Fit Model C once per (bandwidth x sample x industry) combination and
#' return beta4, its SE, p-value, and 95% CI for each.
run_specification_curve <- function(fred_panel, treatment_table, exposure_table,
                                     industries = list(
                                       list(industry = "food_service", col = "employment_food_service"),
                                       list(industry = "retail", col = "employment_retail")
                                     ),
                                     bandwidths = BANDWIDTHS, samples = SAMPLES) {
  specs <- expand.grid(
    bandwidth_label = names(bandwidths), sample_label = names(samples),
    industry_idx = seq_along(industries), stringsAsFactors = FALSE
  )

  rows <- lapply(seq_len(nrow(specs)), function(i) {
    spec <- specs[i, ]
    ind <- industries[[spec$industry_idx]]
    reduced_table <- samples[[spec$sample_label]](treatment_table)
    panel <- build_panel(fred_panel, reduced_table, exposure_table, ind$industry, ind$col,
                          exposure_band_col = bandwidths[[spec$bandwidth_label]])
    ct <- fixest::coeftable(fit_model_c(panel))
    tibble::tibble(
      bandwidth = spec$bandwidth_label,
      sample = spec$sample_label,
      industry = ind$industry,
      beta4 = ct[BETA4_TERM, "Estimate"],
      se = ct[BETA4_TERM, "Std. Error"],
      p_value = ct[BETA4_TERM, "Pr(>|t|)"]
    )
  })

  dplyr::bind_rows(rows) %>%
    mutate(
      ci_low = beta4 - 1.96 * se,
      ci_high = beta4 + 1.96 * se,
      significant = p_value < 0.05
    ) %>%
    arrange(beta4) %>%
    mutate(rank = row_number())
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  spec_curve <- run_specification_curve(fred_panel, treatment_table, exposure_table)
  readr::write_csv(spec_curve, "data/processed/specification_curve.csv")

  cat("\n=== Specification curve summary ===\n")
  cat("Specifications:", nrow(spec_curve), "\n")
  cat("Significant at p < 0.05:", sum(spec_curve$significant), "of", nrow(spec_curve), "\n")
  cat("Sign changes:", length(unique(sign(spec_curve$beta4))), "distinct signs across all specs\n")
  print(spec_curve %>% select(bandwidth, sample, industry, beta4, p_value, significant), width = Inf)

  # Top panel: ranked estimates with CI, colored by significance.
  p_top <- ggplot(spec_curve, aes(x = rank, y = beta4, color = significant)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(ymin = ci_low, ymax = ci_high), size = 0.3) +
    scale_color_manual(values = c(`TRUE` = "#146c52", `FALSE` = "#9aa69c"), guide = "none") +
    labs(x = NULL, y = "beta4 estimate") +
    theme_minimal(base_size = 9) +
    theme(axis.text.x = element_blank())

  # Bottom panel: which choice produced each ranked point.
  choices_long <- spec_curve %>%
    select(rank, bandwidth, sample, industry) %>%
    tidyr::pivot_longer(-rank, names_to = "choice_type", values_to = "choice_value")

  p_bottom <- ggplot(choices_long, aes(x = rank, y = choice_value)) +
    geom_point(size = 1.6, color = "#1b211d") +
    facet_grid(choice_type ~ ., scales = "free_y", switch = "y") +
    labs(x = "Specification (ranked by beta4 estimate)", y = NULL) +
    theme_minimal(base_size = 8) +
    theme(strip.placement = "outside", panel.spacing = unit(0.3, "lines"))

  p_top <- p_top +
    labs(title = "Specification curve: beta4 across every exposure band x sample x industry combination",
         subtitle = paste0(sum(spec_curve$significant), " of ", nrow(spec_curve), " specifications significant at p < 0.05"))

  # Stack the two ggplot objects with base grid rather than pulling in a
  # multi-panel-composition package (patchwork/cowplot/gridExtra) that
  # isn't already part of this project's installed R library.
  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  png("reports/figures/specification_curve.png", width = 8, height = 7, units = "in", res = 150)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(2, 1, heights = grid::unit(c(2, 1.6), "null"))))
  print(p_top, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(p_bottom, vp = grid::viewport(layout.pos.row = 2, layout.pos.col = 1))
  grid::upViewport(0)
  dev.off()
  cat("Saved reports/figures/specification_curve.png\n")
}
