#!/usr/bin/env Rscript

required_packages <- c("forecast", "ggplot2", "tseries", "vars")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Install the missing packages before running the analysis: ",
    paste(missing_packages, collapse = ", ")
  )
}

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(project_root, "R", "analysis_helpers.R"))

analysis <- run_portfolio_analysis(project_root, write_outputs = TRUE)

cat("Analysis completed.\n")
cat(
  "Aligned sample:",
  quarter_label(min(analysis$levels$quarter)), "to",
  quarter_label(max(analysis$levels$quarter)), "\n"
)
cat(
  "Evaluation:",
  quarter_label(min(analysis$rolling$quarter)), "to",
  quarter_label(max(analysis$rolling$quarter)), "\n"
)
cat("Selected unemployment model:", analysis$unemployment_spec$model, "\n")
cat("Selected wage model:", analysis$wage_spec$model, "\n")
cat("Selected VAR lag:", analysis$var_lag, "\n\n")
print(analysis$metrics, row.names = FALSE)
