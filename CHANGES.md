# Changes from the two-part course submission

The original R Markdown and HTML submissions were preserved unchanged. This is
a separate portfolio rewrite.

## Data meaning and alignment

- Corrected `HOUS448URN` from a supposed quarterly series to its actual monthly
  frequency and averaged exactly three monthly observations per quarter.
- Corrected `ENUC264240010` from “minimum wage” to average weekly wages for
  employees in covered establishments.
- Corrected wage units to dollars per week and unemployment units to percent.
- Aligned observations by parsed quarter dates; removed all unequal-length
  `cbind`/vector-recycling logic.
- Frozen the analysis at 2025 Q1 and recorded retrieval and alignment metadata.
- Added validation for missing quarters, duplicate wage quarters, incomplete
  three-month unemployment quarters, impossible values, and unexpected source
  schemas.
- Documented that the two FRED titles use different historical Houston MSA
  names and that source data may be revised.

## Transformations and diagnostics

- Replaced mislabeled plots and overwritten variables with one explicit
  transformation pipeline.
- Used four-quarter, year-over-year changes for quarterly annual differences;
  removed the erroneous 12-quarter seasonal lag.
- Used log wage growth rather than scaling wages as “millions.”
- Added complementary ADF and KPSS diagnostics and avoided presenting either
  test as proof of stationarity.
- Correctly interpreted a small Ljung–Box p-value as evidence of remaining
  autocorrelation.
- Applied Ljung–Box tests to each fitted model's own residuals and adjusted the
  degrees of freedom for fitted AR/MA terms.

## Model selection and forecasting

- Corrected AR/MA identification language: PACF is commonly informative for AR
  order and ACF for MA order, while final selection uses fitted candidates and
  diagnostics.
- Replaced inconsistent hard-coded model labels with a reproducible SARMA grid.
- Selected the lowest-AICc candidate among models passing the initial residual
  check instead of reporting a model whose residuals were visibly correlated.
- Fit the VAR only after both series were aligned and transformed consistently.
- Removed the invalid fit-on-one-dataset/evaluate-on-an-overwritten-dataset VAR
  workflow.
- Used the same expanding-window, one-quarter-ahead forecast origin for the
  seasonal-naive, univariate SARMA, and VAR models.
- Reported both RMSE and MAE from the 29-quarter evaluation rather than mixing
  in-sample reconstruction error with out-of-sample accuracy.
- Replaced fixed prose numbers with values read from generated result tables.

## Publication and reproducibility

- Removed student numbers, assignment questions, AI-percentage tables, and raw
  team-submission prose.
- Added clear authorship, AI-assistance, permission, and non-causal scope notes.
- Split data refresh, reusable functions, analysis, results, figures, and report
  source into a conventional repository structure.
- Added a one-command rebuild, package checks, fixed seeds where simulation is
  used, a session-information file, and a self-contained HTML report.
- Added prominent limitations for structural breaks, data revision, geographic
  definitions, model-selection uncertainty, and the COVID-era evaluation.
