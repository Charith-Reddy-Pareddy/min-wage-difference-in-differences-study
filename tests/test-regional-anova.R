library(testthat)
source("../R/14_regional_anova.R")

test_that("regional_anova detects a region effect that's actually there", {
  set.seed(1)
  state_level <- tibble::tibble(
    region = rep(c("West", "South", "Northeast"), each = 10),
    log_change_food_service = c(rnorm(10, mean = 0.10, sd = 0.01),
                                 rnorm(10, mean = -0.05, sd = 0.01),
                                 rnorm(10, mean = 0.00, sd = 0.01))
  )
  model <- regional_anova(state_level, "log_change_food_service")
  s <- summary(model)[[1]]
  expect_true(s["region", "Pr(>F)"] < 0.001)
})

test_that("regional_anova finds no effect when regions don't actually differ", {
  set.seed(2)
  state_level <- tibble::tibble(
    region = rep(c("West", "South", "Northeast"), each = 10),
    log_change_food_service = rnorm(30, mean = 0.05, sd = 0.05)
  )
  model <- regional_anova(state_level, "log_change_food_service")
  s <- summary(model)[[1]]
  expect_true(s["region", "Pr(>F)"] > 0.05)
})

test_that("save_regional_boxplot writes a plot file", {
  state_level <- tibble::tibble(
    region = rep(c("West", "South"), each = 4),
    group = rep(c("treated", "control"), times = 4),
    log_change_food_service = rnorm(8, sd = 0.05)
  )
  out_dir <- withr::local_tempdir()
  save_regional_boxplot(state_level, "log_change_food_service", out_dir)
  expect_true(file.exists(file.path(out_dir, "regional_boxplot_log_change_food_service.png")))
})
