# Pull state-quarter employment, GDP, and population from FRED.
#
# All three come from FRED's public fredgraph.csv endpoint, which doesn't
# require an API key for a single-series pull (only FRED's JSON/search API
# does). Series IDs were confirmed by direct request, not guessed from
# documentation alone -- see the state FIPS crosswalk below.
#
# Employment series are CES (Current Employment Statistics), not
# seasonally adjusted, monthly, in thousands. QCEW ultimately benchmarks
# these (per the proposal's data-source table), so a separate QCEW
# employment pull isn't needed here -- QCEW's own role is the Day 3
# exposure-validation correlation check, not the outcome series.

library(dplyr)
library(httr)
library(readr)

STATE_FIPS <- c(
  Alaska = "02", Arizona = "04", Arkansas = "05", California = "06",
  Colorado = "08", Illinois = "17", Maine = "23", Maryland = "24",
  Massachusetts = "25", Michigan = "26", Minnesota = "27", Missouri = "29",
  Montana = "30", "New Jersey" = "34", "New Mexico" = "35", "New York" = "36",
  Ohio = "39", "South Dakota" = "46", Vermont = "50", Washington = "53",
  Connecticut = "09", Florida = "12", Nevada = "32", Oregon = "41",
  Virginia = "51"
)

STATE_ABBR <- c(
  Alaska = "AK", Arizona = "AZ", Arkansas = "AR", California = "CA",
  Colorado = "CO", Illinois = "IL", Maine = "ME", Maryland = "MD",
  Massachusetts = "MA", Michigan = "MI", Minnesota = "MN", Missouri = "MO",
  Montana = "MT", "New Jersey" = "NJ", "New Mexico" = "NM", "New York" = "NY",
  Ohio = "OH", "South Dakota" = "SD", Vermont = "VT", Washington = "WA",
  Connecticut = "CT", Florida = "FL", Nevada = "NV", Oregon = "OR",
  Virginia = "VA"
)

#' Build a state CES employment series ID.
#' industry: "70722" (food service) or "42000" (retail trade)
fred_employment_id <- function(state, industry) {
  if (!state %in% names(STATE_FIPS)) stop("Unknown state: ", state)
  paste0("SMU", STATE_FIPS[[state]], "00000", industry, "00001")
}

fred_gdp_id <- function(state) {
  if (!state %in% names(STATE_ABBR)) stop("Unknown state: ", state)
  paste0(STATE_ABBR[[state]], "NQGSP")
}

fred_population_id <- function(state) {
  if (!state %in% names(STATE_ABBR)) stop("Unknown state: ", state)
  paste0(STATE_ABBR[[state]], "POP")
}

fetch_fred_series <- function(series_id) {
  url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=", series_id)
  resp <- GET(url, timeout(30))
  stop_for_status(resp, task = paste("fetching FRED series", series_id))
  df <- read_csv(content(resp, as = "text", encoding = "UTF-8"), col_types = cols())
  names(df) <- c("date", "value")
  df$series_id <- series_id
  df
}

#' Quarterly average of a monthly series.
to_quarterly <- function(df) {
  df %>%
    mutate(quarter = as.Date(cut(date, "quarter"))) %>%
    group_by(quarter) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop")
}

#' Population is annual; repeat each year's value across that year's four
#' quarters so it can join onto the quarterly panel.
annual_to_quarterly <- function(df) {
  df %>%
    mutate(year = as.integer(format(date, "%Y"))) %>%
    tidyr::crossing(q = 1:4) %>%
    transmute(quarter = as.Date(paste0(year, "-", (q - 1) * 3 + 1, "-01")), value)
}

# FRED doesn't publish this exact CES state/industry cell for every state --
# New Mexico and South Dakota both 404 on the food-service series
# (confirmed by direct request, not assumed). This is the kind of
# suppression/availability gap the proposal's Section 4.3 anticipates
# checking for. QCEW's Open Data API has the same private-sector NAICS 722
# and 44-45 (retail) employment for every state, quarterly, back through
# 2015, so it's the fallback for those two states rather than leaving a
# hole in the panel.
QCEW_INDUSTRY <- c(food_service = "722", retail = "44-45")

qcew_area_fips <- function(state) {
  if (!state %in% names(STATE_FIPS)) stop("Unknown state: ", state)
  paste0(STATE_FIPS[[state]], "000")
}

#' QCEW reports raw headcounts; FRED's CES series (the primary source) are
#' in thousands. Convert so the two sources are on the same scale wherever
#' a state mixes FRED and QCEW across its two employment series.
qcew_monthly_to_thousands <- function(month1, month2, month3) {
  mean(as.numeric(c(month1, month2, month3))) / 1000
}

fetch_qcew_quarter <- function(area_fips, industry_code, year, qtr) {
  url <- paste0("https://data.bls.gov/cew/data/api/", year, "/", qtr, "/area/", area_fips, ".csv")
  resp <- GET(url, timeout(30))
  stop_for_status(resp, task = paste("fetching QCEW", area_fips, year, "Q", qtr))
  df <- read_csv(content(resp, as = "text", encoding = "UTF-8"), col_types = cols(.default = "c"))

  row <- df %>% filter(industry_code == !!industry_code, own_code == "5")
  if (nrow(row) != 1) {
    stop("Expected exactly one private-sector QCEW row for ", area_fips, "/", industry_code,
         " ", year, "Q", qtr, ", found ", nrow(row))
  }

  value <- qcew_monthly_to_thousands(row$month1_emplvl, row$month2_emplvl, row$month3_emplvl)
  tibble(quarter = as.Date(paste0(year, "-", (qtr - 1) * 3 + 1, "-01")), value = value)
}

fetch_qcew_employment_quarterly <- function(state, industry, start_date, end_date) {
  area_fips <- qcew_area_fips(state)
  industry_code <- QCEW_INDUSTRY[[industry]]
  years <- as.integer(format(start_date, "%Y")):as.integer(format(end_date, "%Y"))

  quarters <- expand.grid(year = years, qtr = 1:4) %>%
    arrange(year, qtr)

  rows <- purrr::pmap(quarters, function(year, qtr) {
    fetch_qcew_quarter(area_fips, industry_code, year, qtr)
  })
  bind_rows(rows) %>% filter(quarter >= start_date, quarter <= end_date)
}

#' Employment for one state/industry, quarterly. Tries FRED first (needs a
#' monthly-to-quarterly aggregation); falls back to QCEW (already quarterly)
#' if FRED doesn't have that series.
fetch_employment_quarterly <- function(state, fred_industry, qcew_industry, start_date, end_date) {
  tryCatch(
    {
      series <- fetch_fred_series(fred_employment_id(state, fred_industry))
      list(source = "fred", raw = series, quarterly = to_quarterly(series))
    },
    error = function(e) {
      message("  FRED series unavailable for ", state, "/", fred_industry,
              " (", conditionMessage(e), ") -- falling back to QCEW")
      quarterly <- fetch_qcew_employment_quarterly(state, qcew_industry, start_date, end_date)
      list(source = "qcew", raw = quarterly, quarterly = quarterly)
    }
  )
}

fetch_all_fred_data <- function(states = names(STATE_FIPS),
                                 start_date = as.Date("2015-01-01"),
                                 end_date = as.Date("2022-12-31"),
                                 raw_dir = "data/raw/fred",
                                 processed_path = "data/processed/fred_state_quarter.csv") {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  rows <- list()
  sources_used <- list()

  for (state in states) {
    message("Fetching employment data for ", state, "...")

    food <- fetch_employment_quarterly(state, "70722", "food_service", start_date, end_date)
    retail <- fetch_employment_quarterly(state, "42000", "retail", start_date, end_date)
    gdp <- fetch_fred_series(fred_gdp_id(state))
    population <- fetch_fred_series(fred_population_id(state))

    write_csv(food$raw, file.path(raw_dir, paste0(state, "_food_service_", food$source, ".csv")))
    write_csv(retail$raw, file.path(raw_dir, paste0(state, "_retail_", retail$source, ".csv")))
    write_csv(gdp, file.path(raw_dir, paste0(state, "_gdp.csv")))
    write_csv(population, file.path(raw_dir, paste0(state, "_population.csv")))

    sources_used[[state]] <- c(food_service = food$source, retail = retail$source)

    food_q <- food$quarterly %>% rename(employment_food_service = value)
    retail_q <- retail$quarterly %>% rename(employment_retail = value)
    gdp_q <- gdp %>% transmute(quarter = date, gdp = value)
    pop_q <- annual_to_quarterly(population) %>% rename(population = value)

    panel <- food_q %>%
      inner_join(retail_q, by = "quarter") %>%
      left_join(gdp_q, by = "quarter") %>%
      left_join(pop_q, by = "quarter") %>%
      filter(quarter >= start_date, quarter <= end_date) %>%
      mutate(state = state, .before = 1)

    rows[[state]] <- panel

    Sys.sleep(0.5) # be polite to the public endpoints
  }

  combined <- bind_rows(rows)
  dir.create(dirname(processed_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(combined, processed_path)

  fallback_states <- names(sources_used)[vapply(sources_used, function(s) any(s == "qcew"), logical(1))]
  if (length(fallback_states) > 0) {
    message("Used QCEW fallback (FRED series unavailable) for: ", paste(fallback_states, collapse = ", "))
  }

  combined
}

if (sys.nframe() == 0) {
  panel <- fetch_all_fred_data()
  cat("Pulled", nrow(panel), "state-quarter rows for", n_distinct(panel$state), "states\n")
}
