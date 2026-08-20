# Three summary figures for the README's "Key Figures" section, built
# from already-computed data/processed/ outputs. Not part of the
# numbered R/01-16 analysis pipeline -- these are presentation figures,
# not new results, so they live in scripts/ rather than R/.

library(dplyr)
library(ggplot2)

dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)

# 1. Treatment status and wage-increase size. A geographic map would
# need the maps/usmap package (not otherwise a project dependency); a
# sorted bar chart of the 20 treated states' increase size, against a
# labeled count of the zero-change control states, shows the same
# treated/control split plus the increase *magnitude* a plain map
# can't -- without listing 25 identical zero-height control bars.
treatment <- readr::read_csv("data/treatment_classification.csv", show_col_types = FALSE)
n_control <- sum(treatment$group == "control")

p_treatment <- treatment %>%
  filter(group == "treated") %>%
  mutate(state = forcats::fct_reorder(state, increase)) %>%
  ggplot(aes(x = state, y = increase)) +
  geom_col(fill = "#d95f02") +
  coord_flip() +
  labs(
    title = "2021 minimum-wage increase, 20 treated states",
    subtitle = paste0("Plus ", n_control, " zero-change control states (not shown) and 5 excluded later-2021-changers"),
    x = NULL, y = "Wage increase ($)"
  ) +
  theme_minimal(base_size = 10)

ggsave("reports/figures/treatment_control_overview.png", p_treatment, width = 7.5, height = 6, dpi = 150)

# 2. Baseline vs. COVID-adjusted Model A estimate, both industries --
# the headline robustness finding (R/09_covid_sensitivity.R).
covid <- readr::read_csv("data/processed/covid_sensitivity_results.csv", show_col_types = FALSE)

p_covid <- covid %>%
  select(industry, baseline = model_a_treated_post_baseline, covid_adjusted = model_a_treated_post_covid_spec) %>%
  tidyr::pivot_longer(-industry, names_to = "specification", values_to = "estimate") %>%
  mutate(specification = factor(specification, levels = c("baseline", "covid_adjusted"),
                                 labels = c("Baseline", "COVID-adjusted"))) %>%
  ggplot(aes(x = industry, y = estimate, fill = specification)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  geom_hline(yintercept = 0, color = "grey30") +
  scale_fill_manual(values = c(Baseline = "#7570b3", `COVID-adjusted` = "#1b9e77")) +
  labs(
    title = "Model A: baseline vs. COVID-adjusted estimate",
    subtitle = "treated_post coefficient shrinks toward zero once covid_severity x post is included",
    x = NULL, y = "Model A treated_post coefficient", fill = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top")

ggsave("reports/figures/covid_adjustment_comparison.png", p_covid, width = 6, height = 5, dpi = 150)

# 3. Exposure distribution by industry (R/05_exposure_validation.R's
# distribution check) -- food service sits systematically higher than
# retail, the precondition Model C's exposure interaction depends on.
exposure <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

p_exposure <- exposure %>%
  mutate(industry = recode(industry, food_service = "Food service", retail = "Retail")) %>%
  ggplot(aes(x = industry, y = exposure_share_125, fill = industry)) +
  geom_boxplot(width = 0.5, show.legend = FALSE) +
  geom_jitter(width = 0.08, alpha = 0.4, size = 1, color = "grey20") +
  scale_fill_manual(values = c(`Food service` = "#d95f02", Retail = "#7570b3")) +
  labs(
    title = "Pre-2021 exposure share by industry",
    subtitle = "Share of CPS-ORG respondents within 12.5% of the state minimum wage, all 50 states",
    x = NULL, y = "Exposure share"
  ) +
  theme_minimal(base_size = 10)

ggsave("reports/figures/exposure_distribution.png", p_exposure, width = 6, height = 5, dpi = 150)

cat("Saved treatment_control_overview.png, covid_adjustment_comparison.png, exposure_distribution.png to reports/figures/\n")
