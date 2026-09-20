# Identification diagram for the report's "Identification Strategy"
# section and the README. Not a generic textbook DAG -- the backdoor
# path drawn here (Exposure -> Treatment, Exposure -> COVID Severity ->
# Employment) is this project's own actual confounding structure,
# established empirically by R/25 (exposure-COVID correlation) and
# R/30 (exposure predicts treatment, AUC=0.97), not assumed. Presentation
# figure, not a new result -- lives in scripts/, not R/, matching
# generate_readme_figures.R's convention.

library(ggplot2)

nodes <- tibble::tibble(
  name = c("Exposure", "Treatment", "COVID Severity", "Employment"),
  x = c(0, 2.4, 2.4, 4.8),
  y = c(1.6, 1.6, -0.4, 0.6),
  role = c("moderator", "treatment", "confounder", "outcome")
)

straight_edges <- tibble::tibble(
  x = c(0, 0, 2.4, 2.4),
  y = c(1.6, 1.6, -0.4, 1.6),
  xend = c(2.4, 2.4, 4.8, 4.8),
  yend = c(1.6, -0.4, 0.6, 0.6),
  path = c(
    "Backdoor path (confounding)", "Backdoor path (confounding)", "Backdoor path (confounding)",
    "Causal effect of interest (β3)"
  )
)
curved_edges <- tibble::tibble(
  x = 0, y = 1.6, xend = 4.8, yend = 0.6,
  path = "Exposure interaction (β4, Model C)"
)

path_colors <- c(
  "Backdoor path (confounding)" = "#9a3324",
  "Causal effect of interest (β3)" = "#3d6b6b",
  "Exposure interaction (β4, Model C)" = "#8a8578"
)

p <- ggplot() +
  geom_segment(
    data = straight_edges, aes(x = x, y = y, xend = xend, yend = yend, color = path),
    linewidth = 1, arrow = arrow(length = unit(0.22, "cm"), type = "closed")
  ) +
  geom_curve(
    data = curved_edges, aes(x = x, y = y, xend = xend, yend = yend, color = path),
    curvature = -0.35, linewidth = 1,
    arrow = arrow(length = unit(0.22, "cm"), type = "closed")
  ) +
  geom_label(
    data = nodes, aes(x = x, y = y, label = name, fill = role),
    color = "white", fontface = "bold", size = 4.2, label.padding = unit(0.4, "lines")
  ) +
  annotate("text", x = 1.2, y = 1.75, label = "predicts (AUC=0.97)", size = 3, color = "#9a3324") +
  annotate("text", x = 0.7, y = 0.45, label = "r=-0.35 to -0.54", size = 3, color = "#9a3324", angle = -32) +
  annotate("text", x = 3.75, y = -0.05, label = "R/09, R/26", size = 3, color = "#9a3324") +
  annotate("text", x = 3.6, y = 1.35, label = "of interest", size = 3, color = "#3d6b6b") +
  annotate("text", x = 2.4, y = 2.55, label = "estimand (Model C)", size = 3, color = "#8a8578") +
  scale_fill_manual(values = c(
    moderator = "#8a8578", treatment = "#9a3324", confounder = "#c8785f", outcome = "#3d6b6b"
  ), guide = "none") +
  scale_color_manual(values = path_colors, name = NULL) +
  coord_cartesian(xlim = c(-0.6, 5.6), ylim = c(-1.1, 2.9), clip = "off") +
  labs(
    title = "Identification structure: the actual confounding path this study found",
    subtitle = "Red path is empirically established (R/09, R/25, R/26, R/30), not assumed — see report Section 8.1 and Appendix C"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, margin = margin(b = 4)),
    plot.subtitle = element_text(hjust = 0.5, size = 9, color = "grey40", margin = margin(b = 14)),
    legend.position = "bottom"
  )

dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
ggsave("reports/figures/identification_dag.png", p, width = 8.5, height = 5.5, dpi = 150)
cat("Saved reports/figures/identification_dag.png\n")
