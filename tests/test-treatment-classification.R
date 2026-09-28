library(testthat)
source("../R/01_treatment_classification.R")

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
  problems <- validate_treatment_table(df)
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
  df$group[1] <- "bogus"
  problems <- validate_treatment_table(df)
  expect_true(any(grepl("unexpected group values", problems)))
})

test_that("the real treatment table passes validation", {
  df <- load_treatment_table("../data/treatment_classification.csv")
  problems <- validate_treatment_table(df)
  expect_length(problems, 0)
})


test_that("zero-increase states cannot be classified as treated", {
  df <- make_valid_df()
  df$wage_2021[1] <- df$wage_2020[1]
  df$increase[1] <- 0
  expect_true(any(grepl("treated states must have a positive increase", validate_treatment_table(df))))
})

test_that("control states cannot have a recorded wage increase", {
  df <- make_valid_df()
  df$group[1] <- "control"
  expect_true(any(grepl("control states must have zero increase", validate_treatment_table(df))))
})

test_that("Michigan is a no-change control in 2021", {
  df <- load_treatment_table("../data/treatment_classification.csv")
  mi <- df[df$state == "Michigan", ]
  expect_equal(mi$group, "control")
  expect_equal(mi$increase, 0)
  expect_true(is.na(mi$effective_date))
})


test_that("the real sample has 19 treated and 26 control states", {
  df <- load_treatment_table("../data/treatment_classification.csv")
  expect_equal(sum(df$group == "treated"), 19)
  expect_equal(sum(df$group == "control"), 26)
  expect_equal(sum(df$group == "excluded"), 5)
})
