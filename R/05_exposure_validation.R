# Two validation checks on the CPS-ORG exposure measure (Section 3 / 5 of
# the proposal):
#
#  1. QCEW correlation check: QCEW's average wage (converted to an hourly
#     proxy) divided by the contemporaneous state minimum wage, correlated
#     against the CPS-ORG exposure share. States where CPS-ORG says many
#     workers sit near the minimum wage should show LOW QCEW-wage/min-wage
#     ratios -- i.e. a negative correlation is the expected, healthy
#     signal. A weak or wrong-signed correlation is what gets flagged.
#
#  2. Exposure-distribution check: confirm food service and retail
#     actually differ in exposure before that difference is used
#     anywhere downstream (Section 5).
#
# Both pool 2019-2020, matching the exposure measure's own pre-period-only
# window (Section 3) -- using treatment-period QCEW wages here would be
# an inconsistent comparison, not just a style choice.

library(dplyr)

# R/02_fetch_fred_data.R's STATE_FIPS used to be duplicated here instead
# of source()-d, on the reasoning that a 25-line mapping wasn't worth
# path fragility. That duplicate silently went stale the moment Day 5
# added 25 control states to R/02's copy -- caught by the Day 10
# reproducibility check ("Unknown state: Alabama"), not by inspection.
# Switched to the same source()-both-paths pattern R/07 onward already
# uses, which can't drift out of sync since there's only one copy.
if (file.exists("R/02_fetch_fred_data.R")) {
  source("R/02_fetch_fred_data.R")
} else {
  source("../R/02_fetch_fred_data.R")
}

QCEW_WAGE_INDUSTRY <- c(food_service = "722", retail = "44-45")

#' Both industries' QCEW average weekly wage for one state-quarter, in a
#' single request (own_code "5" = private sector).
fetch_qcew_wages_quarter <- function(area_fips, year, qtr) {
  url <- paste0("https://data.bls.gov/cew/data/api/", year, "/", qtr, "/area/", area_fips, ".csv")
  resp <- httr::GET(url, httr::timeout(30))
  httr::stop_for_status(resp, task = paste("fetching QCEW wages", area_fips, year, "Q", qtr))
  df <- readr::read_csv(httr::content(resp, as = "text", encoding = "UTF-8"),
                         col_types = readr::cols(.default = "c"))

  df %>%
    filter(industry_code %in% QCEW_WAGE_INDUSTRY, own_code == "5") %>%
    transmute(
      industry = names(QCEW_WAGE_INDUSTRY)[match(industry_code, QCEW_WAGE_INDUSTRY)],
      avg_wkly_wage = as.numeric(avg_wkly_wage)
    )
}

#' Average QCEW weekly wage per state-industry, pooled across every
#' quarter in [start_date, end_date].
fetch_qcew_avg_wages <- function(states, start_date = as.Date("2019-01-01"),
                                  end_date = as.Date("2020-12-31")) {
  years <- as.integer(format(start_date, "%Y")):as.integer(format(end_date, "%Y"))
  quarters <- expand.grid(year = years, qtr = 1:4)

  rows <- list()
  for (state in states) {
    area_fips <- qcew_area_fips(state)
    state_rows <- purrr::pmap(quarters, function(year, qtr) {
      fetch_qcew_wages_quarter(area_fips, year, qtr) %>% mutate(state = state)
    })
    rows[[state]] <- bind_rows(state_rows)
    Sys.sleep(0.3)
  }

  bind_rows(rows) %>%
    group_by(state, industry) %>%
    summarise(qcew_avg_wkly_wage = mean(avg_wkly_wage, na.rm = TRUE), .groups = "drop")
}

#' QCEW's average wage as an hourly-equivalent proxy (divide by a
#' standard 40-hour week), over the contemporaneous state minimum wage.
qcew_wage_ratio <- function(qcew_avg_wkly_wage, min_wage) {
  (qcew_avg_wkly_wage / 40) / min_wage
}

#' Pearson correlation between the QCEW wage ratio and the CPS-ORG
#' exposure share, run separately per industry (pooling the two would mix
#' two different wage levels together and isn't what Section 3 asks for).
qcew_correlation_check <- function(exposure, qcew_wages, flag_threshold = -0.3) {
  combined <- exposure %>%
    inner_join(qcew_wages, by = c("state", "industry"))

  combined %>%
    group_by(industry) %>%
    summarise(
      correlation = cor(qcew_wage_ratio, exposure_share_15),
      n_states = n(),
      .groups = "drop"
    ) %>%
    mutate(flagged = correlation > flag_threshold) # expect negative; flag if not negative enough
}

#' Paired comparison of food-service vs. retail exposure across states
#' (Section 5): are they actually different before that difference gets
#' used downstream?
exposure_distribution_check <- function(exposure) {
  wide <- exposure %>%
    select(state, industry, exposure_share_15) %>%
    tidyr::pivot_wider(names_from = industry, values_from = exposure_share_15)

  test <- wilcox.test(wide$food_service, wide$retail, paired = TRUE, exact = FALSE)

  list(
    n_states = nrow(wide),
    n_food_higher = sum(wide$food_service > wide$retail),
    mean_food_service = mean(wide$food_service),
    mean_retail = mean(wide$retail),
    wilcoxon_p_value = test$p.value
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  exposure <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  qcew_wages <- fetch_qcew_avg_wages(treatment_table$state)
  qcew_wages <- qcew_wages %>%
    inner_join(treatment_table %>% select(state, min_wage = wage_2020), by = "state") %>%
    mutate(qcew_wage_ratio = qcew_wage_ratio(qcew_avg_wkly_wage, min_wage))

  readr::write_csv(qcew_wages, "data/processed/qcew_wage_ratio.csv")

  correlation_result <- qcew_correlation_check(exposure, qcew_wages)
  readr::write_csv(correlation_result, "data/processed/qcew_correlation_check.csv")
  cat("--- QCEW correlation check ---\n")
  print(correlation_result)

  distribution_result <- exposure_distribution_check(exposure)
  readr::write_csv(
    tibble::as_tibble(distribution_result),
    "data/processed/exposure_distribution_check.csv"
  )
  cat("\n--- Exposure-distribution check (food service vs. retail) ---\n")
  str(distribution_result)
}
