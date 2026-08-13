# Pull CPS-ORG microdata from IPUMS-CPS for exposure construction.
#
# BLOCKED until an IPUMS API key exists. To unblock:
#   1. Register at https://cps.ipums.org/cps and request an API key from
#      your account page.
#   2. install.packages("ipumsr")
#   3. Add a line to a local .env (gitignored, never commit it):
#        IPUMS_API_KEY=paste-your-key-here
#   4. source("R/03_fetch_cps_org.R") and call fetch_cps_org_extract().
#
# Per Section 3 of the proposal: exposure uses ONLY 2019-2020 earnings
# (pre-treatment), so this extract is deliberately scoped to those two
# years -- pulling post-2021 earnings here would let the outcome
# contaminate the exposure covariate.

library(dplyr)

CPS_ORG_SAMPLES <- c("cps2019_01s", "cps2020_01s") # ORG samples, 2019 & 2020

#' Build (not submit) the IPUMS-CPS extract definition for exposure
#' construction. Kept separate from submission so the request shape can be
#' reviewed/tested without an API key or network access.
build_cps_org_extract <- function() {
  ipumsr::define_extract_cps(
    description = "Minimum-wage exposure construction (2019-2020 ORG earnings)",
    samples = CPS_ORG_SAMPLES,
    variables = c(
      "STATEFIP",   # state, for the state-industry cell
      "IND1990",    # industry, to identify food service / retail
      "EARNWT",     # ORG earnings weight -- required for wage statistics
      "HOURWAGE",   # hourly wage (top-coded / allocated flags below)
      "EARNWEEK",   # weekly earnings, for workers not paid hourly
      "UHRSWORKORG", # usual hours worked, to derive hourly pay from weekly
      "QHRSWORKORG", # allocation flag for UHRSWORKORG
      "PAIDHOUR",   # whether paid hourly
      "EARNWT",
      "ORGWT"
    )
  )
}

#' Submit the extract, wait for IPUMS to process it, and download the
#' microdata. Requires IPUMS_API_KEY (see header). Not called by tests --
#' this hits IPUMS's real extract system and can take several minutes.
fetch_cps_org_extract <- function(download_dir = "data/raw/cps_org") {
  api_key <- Sys.getenv("IPUMS_API_KEY")
  if (identical(api_key, "")) {
    stop("IPUMS_API_KEY is not set. See the header of this script for setup steps.")
  }
  if (!requireNamespace("ipumsr", quietly = TRUE)) {
    stop("Package 'ipumsr' is not installed. Run install.packages(\"ipumsr\").")
  }

  dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)

  extract <- build_cps_org_extract()
  submitted <- ipumsr::submit_extract(extract, api_key = api_key)
  ipumsr::wait_for_extract(submitted, api_key = api_key)
  ipumsr::download_extract(submitted, download_dir = download_dir, api_key = api_key)
}

if (sys.nframe() == 0) {
  fetch_cps_org_extract()
}
