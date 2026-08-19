# Day 9: two-sample t-test and descriptive statistics (Section 10,
# STAT 240 coursework closure).
#
# "A formal comparison of pre-period (2019-2020) employment trends
# between treated and control states, as a discrete STAT 240 deliverable
# separate from the event study." Pre-period trend per state is defined
# as log(employment at 2020 Q4) - log(employment at 2019 Q1) -- the same
# two-point log-change pattern used throughout this project (Day 4's
# period_log_change, Day 7's COVID severity measure), just scoped to
# 2019-2020 only rather than pre-vs-post-treatment. This is a simpler,
# STAT-240-level complement to the event study's full quarter-by-quarter
# picture, not a replacement for it.

library(dplyr)

PRE_PERIOD_START <- as.Date("2019-01-01")
PRE_PERIOD_END <- as.Date("2020-10-01")

#' log(employment at PRE_PERIOD_END) - log(employment at PRE_PERIOD_START),
#' per state. Two filtered lookups joined by state (not pivot_wider) --
#' the same fix Day 7's COVID-severity bug needed, for the same reason.
compute_pre_period_trend <- function(fred_panel, outcome_col) {
  start <- fred_panel %>%
    filter(quarter == PRE_PERIOD_START) %>%
    select(state, start_value = all_of(outcome_col))
  end <- fred_panel %>%
    filter(quarter == PRE_PERIOD_END) %>%
    select(state, end_value = all_of(outcome_col))

  full_join(start, end, by = "state") %>%
    transmute(state, pre_trend = log(end_value) - log(start_value))
}

#' Two-sample t-test: treated vs. control pre-period trends. Excludes the
#' "excluded" (later-2021-changer) group, matching every other primary
#' specification in this project (R/06, R/07) -- they aren't a clean
#' comparison group for a binary treated/control test.
two_sample_trend_ttest <- function(trend, treatment_table) {
  df <- trend %>%
    inner_join(treatment_table %>% select(state, group), by = "state") %>%
    filter(group %in% c("treated", "control"))

  stats::t.test(pre_trend ~ group, data = df)
}

#' Mean/SD/n of the pre-period trend, by treatment group, industry, and
#' increase type -- covers all three grouping dimensions the proposal
#' asks for in one table rather than three separate cross-tabs.
descriptive_statistics_table <- function(trend_by_industry, treatment_table) {
  trend_by_industry %>%
    inner_join(treatment_table %>% select(state, group, increase_type), by = "state") %>%
    group_by(group, industry, increase_type) %>%
    summarise(
      n = n(),
      mean_pre_trend = mean(pre_trend),
      sd_pre_trend = sd(pre_trend),
      .groups = "drop"
    ) %>%
    arrange(group, industry, increase_type)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)

  trend_by_industry <- bind_rows(
    compute_pre_period_trend(fred_panel, "employment_food_service") %>% mutate(industry = "food_service"),
    compute_pre_period_trend(fred_panel, "employment_retail") %>% mutate(industry = "retail")
  )

  ttest_results <- list()
  for (ind in c("food_service", "retail")) {
    cat("\n============================================================\n")
    cat("Two-sample t-test, pre-period trend --", ind, "\n")
    trend <- trend_by_industry %>% filter(industry == ind)
    test <- two_sample_trend_ttest(trend, treatment_table)
    print(test)

    group_means <- trend %>%
      inner_join(treatment_table %>% select(state, group), by = "state") %>%
      filter(group %in% c("treated", "control")) %>%
      group_by(group) %>%
      summarise(mean_pre_trend = mean(pre_trend), .groups = "drop")

    ttest_results[[ind]] <- tibble::tibble(
      industry = ind,
      mean_treated = group_means$mean_pre_trend[group_means$group == "treated"],
      mean_control = group_means$mean_pre_trend[group_means$group == "control"],
      t_statistic = unname(test$statistic),
      df = unname(test$parameter),
      p_value = test$p.value,
      ci_low = test$conf.int[1],
      ci_high = test$conf.int[2]
    )
  }
  ttest_table <- bind_rows(ttest_results)
  readr::write_csv(ttest_table, "data/processed/two_sample_ttest_results.csv")

  desc_table <- descriptive_statistics_table(trend_by_industry, treatment_table)
  readr::write_csv(desc_table, "data/processed/descriptive_statistics.csv")

  cat("\n\n=== Two-sample t-test summary ===\n")
  print(ttest_table, width = Inf)
  cat("\n=== Descriptive statistics (by group, industry, increase type) ===\n")
  print(desc_table, n = Inf, width = Inf)
}
