# Post-build addition: a new research question, not a re-analysis of the
# existing one -- did the 2021 minimum-wage increases raise EARNINGS in
# low-wage industries, and by how much relative to the dollar size of the
# mandated increase (pass-through)? Everything through R/28 asks whether
# employment fell; this asks whether the policy did the thing it was
# actually meant to do.
#
# DATA LIMITATION, found by direct request (matching R/02's own practice
# of confirming FRED series IDs rather than guessing): BLS/FRED do not
# publish state-level average hourly earnings at the detailed NAICS-722
# (food service) or 44-45 (retail trade) level this study's employment
# analysis uses -- every candidate series ID at that resolution 404s.
# The finest state-level earnings breakdown BLS publishes is the CES
# SUPERSECTOR: "Leisure and Hospitality" (which nests food service, but
# also accommodation and arts/entertainment/recreation) as the closest
# available proxy for food service, and "Trade, Transportation, and
# Utilities" (which nests retail, but also wholesale trade,
# transportation, and utilities) as the closest available proxy for
# retail. Both are broader than the employment analysis's industries, so
# this section answers a related but not identical question: not "did
# retail workers' wages rise" but "did wages in retail's broader
# supersector rise." That substitution is a real limitation, not a
# rounding error -- stated here and repeated wherever these results are
# reported (README, final report).
#
# Reuses build_panel() and fit_model_a() from R/07 unchanged: the wage
# series is joined onto the existing fred_state_quarter.csv panel (for
# its gdp/population growth covariates) and passed in as `outcome_col`,
# so the state/quarter fixed-effects DiD specification is identical to
# the employment analysis, just on a different outcome.

library(dplyr)
library(httr)
library(readr)

if (file.exists("R/02_fetch_fred_data.R")) {
  source("R/02_fetch_fred_data.R")
  source("R/07_model_a_c.R")
} else {
  source("../R/02_fetch_fred_data.R")
  source("../R/07_model_a_c.R")
}

# CES supersector codes, 5-digit padded form (matching R/02's industry
# code convention): "70000" = Leisure and Hospitality, "40000" = Trade,
# Transportation, and Utilities. Data type "00003" = Average Hourly
# Earnings of All Employees, Dollars.
AHE_SUPERSECTOR <- c(food_service_proxy = "70000", retail_proxy = "40000")

#' Build a state CES average-hourly-earnings series ID. supersector: one
#' of AHE_SUPERSECTOR's values.
fred_ahe_id <- function(state, supersector) {
  if (!state %in% names(STATE_FIPS)) stop("Unknown state: ", state)
  paste0("SMU", STATE_FIPS[[state]], "00000", supersector, "00003")
}

#' Pulls both wage-proxy series for every state, quarterly-averages them
#' (to_quarterly(), from R/02), and writes the combined panel to CSV.
fetch_all_wage_data <- function(states = names(STATE_FIPS),
                                 start_date = as.Date("2015-01-01"),
                                 end_date = as.Date("2022-12-31"),
                                 raw_dir = "data/raw/fred",
                                 processed_path = "data/processed/wage_state_quarter.csv") {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  rows <- list()

  for (state in states) {
    message("Fetching wage data for ", state, "...")

    leisure <- fetch_fred_series(fred_ahe_id(state, AHE_SUPERSECTOR[["food_service_proxy"]]))
    trade <- fetch_fred_series(fred_ahe_id(state, AHE_SUPERSECTOR[["retail_proxy"]]))
    write_csv(leisure, file.path(raw_dir, paste0(state, "_wage_food_service_proxy.csv")))
    write_csv(trade, file.path(raw_dir, paste0(state, "_wage_retail_proxy.csv")))

    leisure_q <- to_quarterly(leisure) %>% rename(wage_food_service_proxy = value)
    trade_q <- to_quarterly(trade) %>% rename(wage_retail_proxy = value)

    panel <- leisure_q %>%
      inner_join(trade_q, by = "quarter") %>%
      filter(quarter >= start_date, quarter <= end_date) %>%
      mutate(state = state, .before = 1)
    rows[[state]] <- panel

    Sys.sleep(0.5) # be polite to the public endpoint, matching R/02
  }

  combined <- bind_rows(rows)
  dir.create(dirname(processed_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(combined, processed_path)
  combined
}

#' Attaches the wage-proxy series to the existing fred_state_quarter
#' panel (for gdp/population, already fetched by R/02) so build_panel()
#' from R/07 can be reused completely unchanged.
build_wage_input <- function(fred_panel, wage_data) {
  fred_panel %>% inner_join(wage_data, by = c("state", "quarter"))
}

#' How much of the average treated state's mandated dollar increase
#' (treatment_table$increase) shows up as a dollar increase in the proxy
#' industry's average hourly earnings. `treated_post_coef` is Model A's
#' log-point effect; `baseline_wage` (mean pre-period wage for treated
#' states) converts it to a dollar amount. A ratio near 1 says the wage
#' floor moved about as much as the statute mandated; near 0 says it
#' barely moved; above 1 says wages rose by more than the mandate alone
#' (spillover onto workers already above the new floor, or a confound --
#' this function reports the number, not the causal story behind it).
wage_passthrough_ratio <- function(treated_post_coef, baseline_wage, treatment_table) {
  implied_dollar_increase <- (exp(treated_post_coef) - 1) * baseline_wage
  mandated_dollar_increase <- mean(treatment_table$increase[treatment_table$group == "treated"])
  list(
    implied_dollar_increase = implied_dollar_increase,
    mandated_dollar_increase = mandated_dollar_increase,
    pass_through_ratio = implied_dollar_increase / mandated_dollar_increase
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  wage_data <- fetch_all_wage_data()
  wage_input <- build_wage_input(fred_panel, wage_data)

  proxies <- list(
    list(industry = "food_service", col = "wage_food_service_proxy",
         label = "Leisure & Hospitality (food service proxy)"),
    list(industry = "retail", col = "wage_retail_proxy",
         label = "Trade, Transportation & Utilities (retail proxy)")
  )

  results <- lapply(proxies, function(p) {
    panel <- build_panel(wage_input, treatment_table, exposure_table, p$industry, p$col)
    model <- fit_model_a(panel)
    ct <- fixest::coeftable(model)

    pre_period_treated_wage <- panel %>% filter(treated == 1, post == 0) %>% pull(log_employment) %>% exp() %>% mean()
    pt <- wage_passthrough_ratio(ct["treated_post", "Estimate"], pre_period_treated_wage, treatment_table)

    tibble::tibble(
      proxy_industry = p$label,
      treated_post_log_coef = ct["treated_post", "Estimate"],
      se = ct["treated_post", "Std. Error"],
      p_value = ct["treated_post", "Pr(>|t|)"],
      baseline_wage = pre_period_treated_wage,
      implied_dollar_increase = pt$implied_dollar_increase,
      mandated_dollar_increase = pt$mandated_dollar_increase,
      pass_through_ratio = pt$pass_through_ratio
    )
  })

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/wage_passthrough_results.csv")
  cat("\n=== Wage pass-through: does earnings in the proxy industry rise with treatment? ===\n")
  print(results_table, width = Inf)

  library(ggplot2)
  plot_data <- results_table %>%
    mutate(
      dollar_se = se * baseline_wage, # delta-method approx: d/dx[exp(x)-1] ~= 1 for small x
      ci_low = implied_dollar_increase - 1.96 * dollar_se,
      ci_high = implied_dollar_increase + 1.96 * dollar_se
    )
  p <- ggplot(plot_data, aes(x = proxy_industry)) +
    geom_col(aes(y = mandated_dollar_increase), fill = "grey80", width = 0.5) +
    geom_pointrange(aes(y = implied_dollar_increase, ymin = ci_low, ymax = ci_high),
                     color = "#9a3324", linewidth = 0.8, size = 0.7) +
    labs(
      title = "Wage pass-through: mandated vs. estimated dollar increase",
      subtitle = "Grey bar = avg. mandated statutory increase; red point = estimated proxy-industry wage effect (95% CI)",
      x = NULL, y = "Dollars per hour"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(size = 9))

  dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave("reports/figures/wage_passthrough.png", p, width = 7.5, height = 5, dpi = 150)
  cat("Saved reports/figures/wage_passthrough.png\n")
}
