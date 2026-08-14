library(testthat)
source("../../R/03_fetch_cps_org.R")

make_catalog <- function() {
  months <- sprintf("%02d", 1:12)
  rows <- do.call(rbind, lapply(c(2019, 2020), function(yr) {
    data.frame(
      name = paste0("cps", yr, "_", months, "s"),
      description = paste("IPUMS-CPS,", month.name, yr)
    )
  }))
  # March in both years also has an ASEC sample, using the "b" suffix
  # for the regular monthly file instead of "s" -- this is the real
  # pattern that broke a hardcoded "01s" guess during development.
  rows$name[rows$name %in% c("cps2019_03s", "cps2020_03s")] <-
    c("cps2019_03b", "cps2020_03b")
  asec_rows <- data.frame(
    name = c("cps2019_03s", "cps2020_03s"),
    description = c("IPUMS-CPS, ASEC 2019", "IPUMS-CPS, ASEC 2020")
  )
  rbind(rows, asec_rows)
}

test_that("resolves to exactly 24 monthly samples, excluding ASEC", {
  samples <- resolve_cps_org_samples(make_catalog())
  expect_length(samples, 24)
  expect_false(any(grepl("cps2019_03s|cps2020_03s", samples)))
  expect_true(all(c("cps2019_03b", "cps2020_03b") %in% samples))
  expect_true(all(grepl("^cps(2019|2020)_\\d{2}[bs]$", samples)))
})

test_that("errors on an unexpected month count instead of silently pulling a partial panel", {
  catalog <- make_catalog()
  catalog <- catalog[catalog$name != "cps2019_05s", ] # drop May 2019
  expect_error(resolve_cps_org_samples(catalog), "Expected 24")
})

test_that("errors if a month somehow matches two non-ASEC samples", {
  catalog <- make_catalog()
  catalog <- rbind(catalog, data.frame(name = "cps2019_05b", description = "IPUMS-CPS, May 2019 (revised)"))
  expect_error(resolve_cps_org_samples(catalog), "Ambiguous")
})
