#!/usr/bin/env Rscript

# Download and freeze the two public FRED series used by this portfolio
# reanalysis. Run this script only when intentionally refreshing the snapshot.

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
raw_dir <- file.path(project_root, "data", "raw")
processed_dir <- file.path(project_root, "data", "processed")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

analysis_cutoff <- as.Date("2025-01-01") # 2025 Q1, fixed before modelling
retrieved_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

fred_urls <- c(
  HOUS448URN = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=HOUS448URN",
  ENUC264240010 = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=ENUC264240010"
)

download_fred <- function(series_id, url) {
  destination <- file.path(raw_dir, paste0("fred_", series_id, ".csv"))
  temporary <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)

  utils::download.file(url, temporary, mode = "wb", quiet = TRUE)
  downloaded <- utils::read.csv(temporary, stringsAsFactors = FALSE)

  expected <- c("observation_date", series_id)
  if (!identical(names(downloaded), expected)) {
    stop("Unexpected FRED schema for ", series_id, ".")
  }

  file.copy(temporary, destination, overwrite = TRUE)
  downloaded
}

quarter_start <- function(date) {
  year <- as.integer(format(date, "%Y"))
  month <- as.integer(format(date, "%m"))
  first_month <- ((month - 1L) %/% 3L) * 3L + 1L
  as.Date(sprintf("%04d-%02d-01", year, first_month))
}

unemployment_raw <- download_fred("HOUS448URN", fred_urls[["HOUS448URN"]])
wage_raw <- download_fred("ENUC264240010", fred_urls[["ENUC264240010"]])

unemployment <- data.frame(
  date = as.Date(unemployment_raw$observation_date),
  unemployment_rate = suppressWarnings(as.numeric(unemployment_raw$HOUS448URN))
)
unemployment <- unemployment[stats::complete.cases(unemployment), ]
unemployment <- unemployment[unemployment$date <= analysis_cutoff + 89, ]
unemployment$quarter <- quarter_start(unemployment$date)

monthly_counts <- stats::aggregate(
  unemployment_rate ~ quarter,
  data = unemployment,
  FUN = length
)
names(monthly_counts)[2] <- "months_observed"

unemployment_quarterly <- stats::aggregate(
  unemployment_rate ~ quarter,
  data = unemployment,
  FUN = mean
)
unemployment_quarterly <- merge(
  unemployment_quarterly,
  monthly_counts,
  by = "quarter",
  all.x = TRUE,
  sort = TRUE
)

# A quarterly average is retained only when all three monthly observations exist.
unemployment_quarterly <- unemployment_quarterly[
  unemployment_quarterly$months_observed == 3L &
    unemployment_quarterly$quarter <= analysis_cutoff,
]

wage <- data.frame(
  quarter = quarter_start(as.Date(wage_raw$observation_date)),
  average_weekly_wage_usd = suppressWarnings(as.numeric(wage_raw$ENUC264240010))
)
wage <- wage[stats::complete.cases(wage), ]
wage <- wage[wage$quarter <= analysis_cutoff, ]

if (anyDuplicated(wage$quarter)) {
  stop("The wage series has duplicate observations within a quarter.")
}

aligned <- merge(
  unemployment_quarterly,
  wage,
  by = "quarter",
  all = FALSE,
  sort = TRUE
)

expected_quarters <- seq(min(aligned$quarter), max(aligned$quarter), by = "quarter")
if (!identical(aligned$quarter, expected_quarters)) {
  stop("The aligned quarterly series contains a gap.")
}
if (max(aligned$quarter) != analysis_cutoff) {
  stop("The aligned data do not reach the fixed analysis cutoff.")
}
if (any(aligned$unemployment_rate < 0) || any(aligned$average_weekly_wage_usd <= 0)) {
  stop("The aligned data contain an impossible value.")
}

utils::write.csv(
  aligned,
  file.path(processed_dir, "houston_quarterly_aligned.csv"),
  row.names = FALSE
)

metadata <- data.frame(
  field = c(
    "retrieved_utc",
    "analysis_cutoff",
    "unemployment_series",
    "wage_series",
    "unemployment_aggregation",
    "aligned_start",
    "aligned_end",
    "aligned_quarters"
  ),
  value = c(
    retrieved_utc,
    "2025 Q1",
    "HOUS448URN (monthly)",
    "ENUC264240010 (quarterly)",
    "Arithmetic mean of three monthly unemployment rates in each quarter",
    format(min(aligned$quarter), "%Y-%m-%d"),
    format(max(aligned$quarter), "%Y-%m-%d"),
    nrow(aligned)
  )
)
utils::write.csv(
  metadata,
  file.path(processed_dir, "snapshot_metadata.csv"),
  row.names = FALSE
)

message(
  "Saved ", nrow(aligned), " aligned quarters from ",
  min(aligned$quarter), " through ", max(aligned$quarter), "."
)
