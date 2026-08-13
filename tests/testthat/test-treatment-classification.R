library(testthat)
source("../../R/01_treatment_classification.R")

make_valid_df <- function() {
  tibble::tibble(
    state = c("A", "B"),
    wage_2020 = c(10.00, 11.00),
    wage_2021 = c(10.50, 11.75),
    effective_date = as.Date(c("2021-01-01", "2021-01-01")),
    increase = c(0.50, 0.75),
    increase_type = c("legislation", "legislation"),
    group = c("treated", "excluded")
  )
}

test_that("a well-formed table has no validation problems", {
  df <- make_valid_df()
  # only 2 states here, so relax the "20 treated" rule for this synthetic case
  problems <- validate_treatment_table(df)
  problems <- problems[!grepl("^expected 20 treated", problems)]
  expect_length(problems, 0)
})

test_that("duplicate states are caught", {
  df <- make_valid_df()
  df <- rbind(df, df[1, ])
  problems <- validate_treatment_table(df)
  expect_true(any(grepl("duplicate state rows", problems)))
})

test_that("mismatched increase column is caught", {
  df <- make_valid_df()
  df$increase[1] <- 99
  problems <- validate_treatment_table(df)
  expect_true(any(grepl("increase column doesn't match", problems)))
})

test_that("unexpected group values are caught", {
  df <- make_valid_df()
  df$group[1] <- "control"
  problems <- validate_treatment_table(df)
  expect_true(any(grepl("unexpected group values", problems)))
})

test_that("the real treatment table passes validation", {
  df <- load_treatment_table("../../data/treatment_classification.csv")
  problems <- validate_treatment_table(df)
  expect_length(problems, 0)
})
