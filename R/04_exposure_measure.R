# Build the minimum-wage exposure measure from CPS-ORG microdata.
#
# Per Section 3 of the proposal: exposure is the share of workers in a
# state-industry cell earning within a band of the pre-2021 minimum wage,
# computed ONLY from 2019-2020 earnings (pre-treatment), and it does not
# vary by quarter -- it's a fixed characteristic of the state-industry
# cell, used as a time-invariant interaction term in Model C. So although
# CPS-ORG respondents arrive monthly, the exposure share pools all of
# 2019-2020 together per state-industry; per-quarter breakdowns exist only
# for the distribution check (Section 5), not as the estimand itself.
#
# The proposal states the band as "10-15%" without picking a single
# number, and separately lists "band width choice" as a named source of
# exposure-measure construction risk (Section 13) -- i.e. this is a
# documented open sensitivity parameter, not an oversight. Both endpoints
# are computed; 12.5% (the midpoint) is used as the primary column.

library(dplyr)
library(ipumsr)

FOOD_SERVICE_IND1990 <- 641L

RETAIL_IND1990 <- c(
  580L, 581L, 582L, 590L, 591L, 592L, 600L, 601L, 602L, 610L, 611L, 612L,
  620L, 621L, 622L, 623L, 630L, 631L, 632L, 633L, 640L, 642L, 650L, 651L,
  652L, 660L, 661L, 662L, 663L, 670L, 671L, 672L, 681L, 682L, 691L
) # IND1990's "Retail Trade" division, minus 641 (Eating and drinking
  # places), which is reported as food service instead -- matching how
  # NAICS (and FRED's CES series) separate the two today even though this
  # older Census scheme nests both under one division.

CPS_ORG_MISSING <- list(HOURWAGE = 999.99, EARNWEEK = 9999.99, UHRSWORKORG_MIN_VALID = 998)

#' Hourly wage per respondent: HOURWAGE directly for hourly-paid workers,
#' EARNWEEK / UHRSWORKORG for everyone else. NA where neither is usable.
derive_hourly_wage <- function(hourwage, paidhour, earnweek, uhrsworkorg) {
  hourwage <- as.numeric(hourwage)
  earnweek <- as.numeric(earnweek)
  uhrsworkorg <- as.numeric(uhrsworkorg)
  paidhour <- as.integer(paidhour)

  hourly_valid <- !is.na(hourwage) & hourwage < CPS_ORG_MISSING$HOURWAGE
  from_hourly <- paidhour == 2L & hourly_valid

  hours_valid <- !is.na(uhrsworkorg) & uhrsworkorg > 0 & uhrsworkorg < CPS_ORG_MISSING$UHRSWORKORG_MIN_VALID
  weekly_valid <- !is.na(earnweek) & earnweek < CPS_ORG_MISSING$EARNWEEK
  from_weekly <- !from_hourly & hours_valid & weekly_valid

  wage <- rep(NA_real_, length(hourwage))
  wage[from_hourly] <- hourwage[from_hourly]
  wage[from_weekly] <- earnweek[from_weekly] / uhrsworkorg[from_weekly]
  wage
}

#' "food_service", "retail", or NA (every other industry) for each
#' respondent's IND1990 code.
classify_industry <- function(ind1990) {
  ind1990 <- as.integer(ind1990)
  case_when(
    ind1990 == FOOD_SERVICE_IND1990 ~ "food_service",
    ind1990 %in% RETAIL_IND1990 ~ "retail",
    TRUE ~ NA_character_
  )
}

month_to_quarter <- function(month) {
  ((as.integer(month) - 1L) %/% 3L) + 1L
}

STATE_FIPS_LOOKUP <- c(
  "1" = "Alabama", "2" = "Alaska", "4" = "Arizona", "5" = "Arkansas", "6" = "California",
  "8" = "Colorado", "9" = "Connecticut", "10" = "Delaware", "11" = "District of Columbia",
  "12" = "Florida", "13" = "Georgia", "15" = "Hawaii", "16" = "Idaho", "17" = "Illinois",
  "18" = "Indiana", "19" = "Iowa", "20" = "Kansas", "21" = "Kentucky", "22" = "Louisiana",
  "23" = "Maine", "24" = "Maryland", "25" = "Massachusetts", "26" = "Michigan",
  "27" = "Minnesota", "28" = "Mississippi", "29" = "Missouri", "30" = "Montana",
  "31" = "Nebraska", "32" = "Nevada", "33" = "New Hampshire", "34" = "New Jersey",
  "35" = "New Mexico", "36" = "New York", "37" = "North Carolina", "38" = "North Dakota",
  "39" = "Ohio", "40" = "Oklahoma", "41" = "Oregon", "42" = "Pennsylvania",
  "44" = "Rhode Island", "45" = "South Carolina", "46" = "South Dakota", "47" = "Tennessee",
  "48" = "Texas", "49" = "Utah", "50" = "Vermont", "51" = "Virginia", "53" = "Washington",
  "54" = "West Virginia", "55" = "Wisconsin", "56" = "Wyoming"
)

#' Load the raw CPS-ORG extract, restrict to outgoing-rotation-group
#' respondents (EARNWT > 0), and attach derived wage/industry/quarter.
load_cps_org_microdata <- function(ddi_path = "data/raw/cps_org/cps_00001.xml") {
  ddi <- read_ipums_ddi(ddi_path)
  raw <- read_ipums_micro(ddi, verbose = FALSE)

  raw %>%
    filter(EARNWT > 0) %>%
    transmute(
      state = STATE_FIPS_LOOKUP[as.character(as.integer(STATEFIP))],
      year = YEAR,
      quarter = month_to_quarter(MONTH),
      industry = classify_industry(IND1990),
      wage = derive_hourly_wage(HOURWAGE, PAIDHOUR, EARNWEEK, UHRSWORKORG),
      earnwt = EARNWT
    ) %>%
    filter(!is.na(industry))
}

#' Weighted share of a cell's wage distribution within `band_pct` of
#' `min_wage` (e.g. band_pct = 0.15 -> [0.85, 1.15] x min_wage). CPS-ORG
#' is a weighted sample, so the share uses EARNWT, not a raw headcount.
weighted_exposure_share <- function(wage, earnwt, min_wage, band_pct) {
  valid <- !is.na(wage) & !is.na(earnwt)
  wage <- wage[valid]
  earnwt <- earnwt[valid]
  if (length(wage) == 0) return(NA_real_)

  in_band <- wage >= min_wage * (1 - band_pct) & wage <= min_wage * (1 + band_pct)
  sum(earnwt[in_band]) / sum(earnwt)
}

#' One row per state-industry: exposure share (10%, 12.5%, 15% bands),
#' pooling all 2019-2020 CPS-ORG respondents, plus the raw (unweighted)
#' respondent count used for the N < 30 data-availability check.
build_exposure_table <- function(cps_org, treatment_table) {
  min_wage_by_state <- treatment_table %>% select(state, min_wage = wage_2020)

  cps_org %>%
    inner_join(min_wage_by_state, by = "state") %>%
    group_by(state, industry) %>%
    summarise(
      n_obs = sum(!is.na(wage)),
      exposure_share_10 = weighted_exposure_share(wage, earnwt, first(min_wage), 0.10),
      exposure_share_125 = weighted_exposure_share(wage, earnwt, first(min_wage), 0.125),
      exposure_share_15 = weighted_exposure_share(wage, earnwt, first(min_wage), 0.15),
      .groups = "drop"
    ) %>%
    mutate(below_cell_size_threshold = n_obs < 30)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()

  cps_org <- load_cps_org_microdata()
  exposure <- build_exposure_table(cps_org, treatment_table)

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(exposure, "data/processed/exposure_state_industry.csv")

  flagged <- exposure %>% filter(below_cell_size_threshold)
  if (nrow(flagged) > 0) {
    cat("State-industry cells still under n=30 after pooling all of 2019-2020:\n")
    print(flagged %>% select(state, industry, n_obs))
  } else {
    cat("No state-industry cells below the n=30 threshold.\n")
  }
}
