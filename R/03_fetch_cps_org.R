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

#' Load KEY=VALUE lines from a local .env into the R session's environment
#' variables. No package dependency for something this small; silently does
#' nothing if the file doesn't exist.
load_dotenv <- function(path = ".env") {
  if (!file.exists(path)) return(invisible(NULL))
  lines <- readLines(path, warn = FALSE)
  lines <- lines[grepl("=", lines) & !grepl("^\\s*#", lines)]
  for (line in lines) {
    parts <- strsplit(line, "=", fixed = TRUE)[[1]]
    key <- trimws(parts[1])
    value <- trimws(paste(parts[-1], collapse = "="))
    if (nzchar(key)) do.call(Sys.setenv, setNames(list(value), key))
  }
  invisible(NULL)
}

#' CPS-ORG isn't a separate IPUMS sample type -- it's a subset of
#' respondents (the outgoing rotation groups) within each month's Basic
#' Monthly CPS file, identified by EARNWT > 0. So "the 2019-2020 ORG
#' samples" means all 24 monthly Basic files across both years, not one
#' sample per year. March has an extra ASEC (Annual Social and Economic
#' Supplement) sample alongside the regular monthly one -- ASEC isn't a
#' rotation-group design and doesn't carry ORG earnings the same way, so
#' it's excluded. This is resolved against IPUMS's live sample catalog
#' rather than hardcoded, since guessing the "b" vs "s" suffix per month
#' turned out to be wrong on the first attempt (it isn't a fixed pattern
#' across months).
resolve_cps_org_samples <- function(sample_catalog, years = c(2019, 2020)) {
  pattern <- paste0("^cps(", paste(years, collapse = "|"), ")_(\\d{2})[bs]$")
  candidates <- sample_catalog[grepl(pattern, sample_catalog$name) &
                                  !grepl("ASEC", sample_catalog$description), ]
  key <- sub(pattern, "\\1-\\2", candidates$name)

  dupes <- key[duplicated(key)]
  if (length(dupes) > 0) {
    stop("Ambiguous CPS-ORG sample selection for: ", paste(unique(dupes), collapse = ", "))
  }
  expected <- length(years) * 12
  if (nrow(candidates) != expected) {
    stop("Expected ", expected, " monthly samples, found ", nrow(candidates))
  }

  candidates$name[order(key)]
}

#' Build (not submit) the IPUMS-CPS extract definition for exposure
#' construction. Kept separate from submission so the request shape can be
#' reviewed/tested without an API key or network access.
build_cps_org_extract <- function(samples) {
  ipumsr::define_extract_micro(
    collection = "cps",
    description = "Minimum-wage exposure construction (2019-2020 ORG earnings)",
    samples = samples,
    variables = c(
      "STATEFIP",   # state, for the state-industry cell
      "IND1990",    # industry, to identify food service / retail
      "EARNWT",     # ORG earnings weight -- required for wage statistics
      "HOURWAGE",   # hourly wage (top-coded / allocated flags below)
      "EARNWEEK",   # weekly earnings, for workers not paid hourly
      "UHRSWORKORG", # usual hours worked, to derive hourly pay from weekly
      "PAIDHOUR"    # whether paid hourly
    )
  )
}

#' Submit the extract, wait for IPUMS to process it, and download the
#' microdata. Requires IPUMS_API_KEY (see header). Not called by tests --
#' this hits IPUMS's real extract system and can take several minutes.
fetch_cps_org_extract <- function(download_dir = "data/raw/cps_org") {
  load_dotenv()
  api_key <- Sys.getenv("IPUMS_API_KEY")
  if (identical(api_key, "")) {
    stop("IPUMS_API_KEY is not set. See the header of this script for setup steps.")
  }
  if (!requireNamespace("ipumsr", quietly = TRUE)) {
    stop("Package 'ipumsr' is not installed. Run install.packages(\"ipumsr\").")
  }

  dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)

  sample_catalog <- ipumsr::get_sample_info("cps", api_key = api_key)
  samples <- resolve_cps_org_samples(sample_catalog)

  extract <- build_cps_org_extract(samples)
  submitted <- ipumsr::submit_extract(extract, api_key = api_key)
  ipumsr::wait_for_extract(submitted, api_key = api_key)
  ipumsr::download_extract(submitted, download_dir = download_dir, api_key = api_key)
}

if (sys.nframe() == 0) {
  fetch_cps_org_extract()
}
