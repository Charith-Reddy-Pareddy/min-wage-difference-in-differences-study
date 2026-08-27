# Post-build addition: four independent checks (R/08's beta4 event
# study, R/10's beta4 placebo test, R/15's beta4 permutation test, R/23's
# specification curve) each separately concluded that the exposure
# gradient (beta4) is fragile -- but each lives in its own report
# section, so a reader has to piece the full picture together by hand.
# This pulls all four into one tidy table: what each check found, per
# industry, in one place. No new statistics, just synthesis of results
# already computed elsewhere.

library(dplyr)

#' One row per check, one column per industry, summarizing what each of
#' the four beta4 robustness checks found. `spec_curve` is summarized as
#' "N of 6 significant, sign" per industry rather than a single p-value,
#' since it's 6 specifications per industry rather than one test.
beta4_robustness_summary <- function(placebo_beta4, permutation_beta4, spec_curve, pretrend_beta4) {
  industries <- c("food_service", "retail")

  fmt_p <- function(p) {
    ifelse(p < 0.0001, "p < 0.0001", sprintf("p = %.4f", p))
  }

  by_industry <- function(df, col) {
    setNames(df[[col]][match(industries, df$industry)], industries)
  }

  placebo_p <- by_industry(placebo_beta4, "placebo_beta4_p")
  permutation_p <- by_industry(permutation_beta4, "permutation_p_value")
  permutation_mean <- by_industry(permutation_beta4, "null_mean")
  pretrend_p <- by_industry(pretrend_beta4, "pretrend_p_value")

  spec_curve_summary <- spec_curve %>%
    group_by(industry) %>%
    summarise(
      n_sig = sum(significant),
      n_total = n(),
      n_positive = sum(beta4 > 0),
      n_negative = sum(beta4 < 0),
      .groups = "drop"
    ) %>%
    mutate(
      dominant_sign = ifelse(n_positive >= n_negative, "positive", "negative"),
      n_dominant = pmax(n_positive, n_negative)
    )
  spec_curve_text <- setNames(
    sprintf("%d of %d significant, %s in %d of %d",
            spec_curve_summary$n_sig, spec_curve_summary$n_total,
            spec_curve_summary$dominant_sign, spec_curve_summary$n_dominant, spec_curve_summary$n_total),
    spec_curve_summary$industry
  )

  tibble(
    check = c(
      "Placebo test (false 2018 date)",
      "Permutation test (label reassignment)",
      "Specification curve (12 specs)",
      "Event study (pre-trend joint test)"
    ),
    food_service = unname(c(
      fmt_p(placebo_p["food_service"]),
      paste0(fmt_p(permutation_p["food_service"]),
             ifelse(permutation_mean["food_service"] < -0.01 || permutation_mean["food_service"] > 0.01,
                    " (null not centered at zero)", "")),
      spec_curve_text["food_service"],
      fmt_p(pretrend_p["food_service"])
    )),
    retail = unname(c(
      fmt_p(placebo_p["retail"]),
      paste0(fmt_p(permutation_p["retail"]),
             ifelse(permutation_mean["retail"] < -0.01 || permutation_mean["retail"] > 0.01,
                    " (null not centered at zero)", "")),
      spec_curve_text["retail"],
      fmt_p(pretrend_p["retail"])
    ))
  )
}

if (sys.nframe() == 0) {
  placebo_beta4 <- readr::read_csv("data/processed/placebo_test_beta4_results.csv", show_col_types = FALSE)
  permutation_beta4 <- readr::read_csv("data/processed/permutation_test_beta4_results.csv", show_col_types = FALSE)
  spec_curve <- readr::read_csv("data/processed/specification_curve.csv", show_col_types = FALSE)
  pretrend_beta4 <- readr::read_csv("data/processed/pretrend_joint_test_beta4.csv", show_col_types = FALSE)

  summary_table <- beta4_robustness_summary(placebo_beta4, permutation_beta4, spec_curve, pretrend_beta4)
  readr::write_csv(summary_table, "data/processed/beta4_robustness_summary.csv")
  cat("\n=== beta4 robustness summary (four independent checks) ===\n")
  print(summary_table, width = Inf)
}
