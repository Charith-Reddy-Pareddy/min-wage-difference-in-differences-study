# PDF export of the rendered HTML report, via a headless Chrome print
# (pagedown::chrome_print()) rather than a LaTeX pipeline -- this
# environment has Chrome but no LaTeX distribution, and a full TeX Live
# install is a multi-GB dependency this project doesn't otherwise need.
# Needs reports/final_report.html to already exist (`make report`) and
# Chrome/Chromium installed locally; pagedown auto-detects the browser.
#
# The report's code-folding "Code"/"Show" buttons are hidden in print
# via an `@media print` rule in final_report.Rmd's header -- they toggle
# visibility with JS, which doesn't exist in a static PDF.

if (!requireNamespace("pagedown", quietly = TRUE)) {
  stop("pagedown is not installed -- run renv::restore() first.")
}

pagedown::chrome_print(
  input = "reports/final_report.html",
  output = "reports/final_report.pdf",
  timeout = 180
)

cat("Wrote reports/final_report.pdf\n")
