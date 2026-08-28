#!/usr/bin/env Rscript

script_args <- commandArgs(trailingOnly = FALSE)
script_flag <- grep("^--file=", script_args, value = TRUE)
if (length(script_flag) != 1L) {
  stop("Run this file with Rscript from a local checkout.", call. = FALSE)
}

script_path <- normalizePath(
  sub("^--file=", "", script_flag),
  winslash = "/",
  mustWork = TRUE
)
project_root <- dirname(script_path)
setwd(project_root)

required_packages <- c(
  "forecast", "ggplot2", "knitr", "rmarkdown", "tseries", "vars"
)
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Install the missing packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

source(file.path(project_root, "R", "analysis_helpers.R"))
analysis <- run_portfolio_analysis(project_root, write_outputs = TRUE)

if (!rmarkdown::pandoc_available()) {
  machine <- Sys.info()[["machine"]]
  candidate <- if (identical(machine, "arm64")) {
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64"
  } else {
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/x86_64"
  }
  if (file.exists(file.path(candidate, "pandoc"))) {
    Sys.setenv(RSTUDIO_PANDOC = candidate)
  }
}
if (!rmarkdown::pandoc_available()) {
  stop("Pandoc was not found. Render from RStudio or install Pandoc.", call. = FALSE)
}

rmarkdown::render(
  input = file.path(project_root, "report", "analysis.Rmd"),
  output_file = "analysis.html",
  output_dir = file.path(project_root, "report"),
  knit_root_dir = project_root,
  envir = new.env(parent = globalenv()),
  clean = TRUE,
  quiet = TRUE
)

docs_dir <- file.path(project_root, "docs")
dir.create(docs_dir, recursive = TRUE, showWarnings = FALSE)
copied <- file.copy(
  file.path(project_root, "report", "analysis.html"),
  file.path(docs_dir, "index.html"),
  overwrite = TRUE
)
if (!isTRUE(copied)) stop("Could not copy the report into docs/.", call. = FALSE)

message("Analysis and report completed: ", file.path(project_root, "report", "analysis.html"))
