quarter_label <- function(date) {
  year <- format(as.Date(date), "%Y")
  month <- as.integer(format(as.Date(date), "%m"))
  paste0(year, " Q", ((month - 1L) %/% 3L) + 1L)
}

candidate_specifications <- function() {
  specifications <- expand.grid(
    p = 0:3,
    q = 0:3,
    P = 0:1,
    Q = 0:1
  )
  specifications <- specifications[
    rowSums(specifications) <= 4L,
    c("p", "q", "P", "Q")
  ]
  specifications$model <- sprintf(
    "SARMA(%d,%d)(%d,%d)[4]",
    specifications$p,
    specifications$q,
    specifications$P,
    specifications$Q
  )
  specifications <- specifications[c("model", "p", "q", "P", "Q")]
  rownames(specifications) <- NULL
  specifications
}

fit_candidate <- function(y, spec) {
  forecast::Arima(
    y,
    order = c(spec$p, 0L, spec$q),
    seasonal = list(order = c(spec$P, 0L, spec$Q), period = 4L),
    include.mean = TRUE,
    method = "ML"
  )
}

rank_candidates <- function(y, specifications = candidate_specifications()) {
  output <- vector("list", nrow(specifications))

  for (i in seq_len(nrow(specifications))) {
    spec <- specifications[i, ]
    fitted <- tryCatch(
      fit_candidate(y, spec),
      error = function(e) NULL
    )

    if (is.null(fitted)) {
      output[[i]] <- data.frame(
        model = spec$model,
        p = spec$p,
        q = spec$q,
        P = spec$P,
        Q = spec$Q,
        AICc = Inf,
        AIC = Inf,
        BIC = Inf,
        Ljung_Box_p_value = NA_real_,
        residual_check_passed = FALSE
      )
    } else {
      fitted_parameters <- spec$p + spec$q + spec$P + spec$Q
      residual_test <- stats::Box.test(
        stats::residuals(fitted),
        lag = 12L,
        type = "Ljung-Box",
        fitdf = fitted_parameters
      )
      output[[i]] <- data.frame(
        model = spec$model,
        p = spec$p,
        q = spec$q,
        P = spec$P,
        Q = spec$Q,
        AICc = fitted$aicc,
        AIC = stats::AIC(fitted),
        BIC = stats::BIC(fitted),
        Ljung_Box_p_value = residual_test$p.value,
        residual_check_passed = residual_test$p.value >= 0.05
      )
    }
  }

  ranking <- do.call(rbind, output)
  ranking <- ranking[order(ranking$AICc, ranking$BIC), ]
  ranking$delta_AICc <- ranking$AICc - min(ranking$AICc)
  rownames(ranking) <- NULL
  ranking
}

select_specification <- function(ranking) {
  eligible <- which(ranking$residual_check_passed & is.finite(ranking$AICc))
  if (length(eligible) == 0L) {
    warning("No candidate passed the residual check; selecting by AICc only.")
    selected <- which.min(ranking$AICc)
  } else {
    selected <- eligible[which.min(ranking$AICc[eligible])]
  }
  ranking[selected, c("model", "p", "q", "P", "Q"), drop = FALSE]
}

safe_adf <- function(x) {
  result <- suppressWarnings(tseries::adf.test(x, alternative = "stationary"))
  unname(result$p.value)
}

safe_kpss <- function(x) {
  result <- suppressWarnings(tseries::kpss.test(x, null = "Level"))
  unname(result$p.value)
}

stationarity_tests <- function(levels) {
  series <- list(
    "Unemployment rate (level)" = levels$unemployment_rate,
    "Log weekly wage (level)" = log(levels$average_weekly_wage_usd),
    "Year-over-year change in unemployment" = diff(
      levels$unemployment_rate,
      lag = 4L
    ),
    "Year-over-year log wage growth" = diff(
      log(levels$average_weekly_wage_usd),
      lag = 4L
    )
  )

  data.frame(
    series = names(series),
    observations = vapply(series, length, integer(1)),
    ADF_p_value = vapply(series, safe_adf, numeric(1)),
    KPSS_level_p_value = vapply(series, safe_kpss, numeric(1)),
    row.names = NULL,
    check.names = FALSE
  )
}

select_var_lag <- function(transformed_training, maximum = 4L) {
  selection <- vars::VARselect(
    transformed_training,
    lag.max = maximum,
    type = "const"
  )$selection
  selected <- as.integer(selection[["AIC(n)"]])
  max(1L, selected)
}

model_diagnostics <- function(y, spec, series_name) {
  fitted <- fit_candidate(y, spec)
  lag_used <- min(12L, floor(length(y) / 5L))
  fitted_parameters <- spec$p + spec$q + spec$P + spec$Q
  ljung_box <- stats::Box.test(
    stats::residuals(fitted),
    lag = lag_used,
    type = "Ljung-Box",
    fitdf = fitted_parameters
  )

  data.frame(
    series = series_name,
    selected_model = spec$model,
    residual_test_lag = lag_used,
    Ljung_Box_statistic = unname(ljung_box$statistic),
    Ljung_Box_p_value = ljung_box$p.value,
    residual_conclusion = if (
      ljung_box$p.value >= 0.05
    ) "No residual autocorrelation detected at 5%" else
      "Residual autocorrelation remains at 5%",
    stringsAsFactors = FALSE
  )
}

rolling_evaluation <- function(levels, split_index, unemployment_spec,
                               wage_spec, var_lag) {
  levels$delta_unemployment <- c(
    rep(NA_real_, 4L),
    diff(levels$unemployment_rate, lag = 4L)
  )
  levels$wage_log_growth <- c(
    rep(NA_real_, 4L),
    diff(log(levels$average_weekly_wage_usd), lag = 4L)
  )

  test_indices <- seq.int(split_index + 1L, nrow(levels))
  forecasts <- vector("list", length(test_indices))

  for (j in seq_along(test_indices)) {
    target <- test_indices[j]
    history_rows <- 5L:(target - 1L)

    unemployment_fit <- fit_candidate(
      levels$delta_unemployment[history_rows],
      unemployment_spec
    )
    wage_fit <- fit_candidate(
      levels$wage_log_growth[history_rows],
      wage_spec
    )

    predicted_unemployment_change <- as.numeric(
      forecast::forecast(unemployment_fit, h = 1L)$mean[1]
    )
    predicted_wage_growth <- as.numeric(
      forecast::forecast(wage_fit, h = 1L)$mean[1]
    )

    transformed_history <- data.frame(
      delta_unemployment = levels$delta_unemployment[history_rows],
      wage_log_growth = levels$wage_log_growth[history_rows]
    )
    var_fit <- vars::VAR(transformed_history, p = var_lag, type = "const")
    var_prediction <- predict(var_fit, n.ahead = 1L)$fcst
    var_unemployment_change <- var_prediction$delta_unemployment[1, "fcst"]
    var_wage_growth <- var_prediction$wage_log_growth[1, "fcst"]

    same_quarter_last_year_unemployment <- levels$unemployment_rate[target - 4L]
    same_quarter_last_year_wage <- levels$average_weekly_wage_usd[target - 4L]

    forecasts[[j]] <- data.frame(
      quarter = levels$quarter[target],
      actual_unemployment = levels$unemployment_rate[target],
      actual_wage = levels$average_weekly_wage_usd[target],
      naive_unemployment = same_quarter_last_year_unemployment,
      naive_wage = same_quarter_last_year_wage,
      univariate_unemployment = same_quarter_last_year_unemployment +
        predicted_unemployment_change,
      univariate_wage = exp(
        log(same_quarter_last_year_wage) + predicted_wage_growth
      ),
      var_unemployment = same_quarter_last_year_unemployment +
        var_unemployment_change,
      var_wage = exp(log(same_quarter_last_year_wage) + var_wage_growth)
    )
  }

  do.call(rbind, forecasts)
}

forecast_metrics <- function(rolling) {
  models <- c("Seasonal naive", "Univariate SARMA", "VAR")
  unemployment_columns <- c(
    "naive_unemployment", "univariate_unemployment", "var_unemployment"
  )
  wage_columns <- c("naive_wage", "univariate_wage", "var_wage")

  metric_rows <- list()
  index <- 1L
  for (i in seq_along(models)) {
    for (metric in c("RMSE", "MAE")) {
      unemployment_error <- rolling[[unemployment_columns[i]]] -
        rolling$actual_unemployment
      wage_error <- rolling[[wage_columns[i]]] - rolling$actual_wage

      summarize_error <- if (metric == "RMSE") {
        function(error) sqrt(mean(error^2))
      } else {
        function(error) mean(abs(error))
      }

      metric_rows[[index]] <- data.frame(
        target = "Quarterly unemployment rate",
        model = models[i],
        metric = metric,
        value = summarize_error(unemployment_error)
      )
      metric_rows[[index + 1L]] <- data.frame(
        target = "Average weekly wage (USD)",
        model = models[i],
        metric = metric,
        value = summarize_error(wage_error)
      )
      index <- index + 2L
    }
  }

  output <- do.call(rbind, metric_rows)
  output[order(output$target, output$metric, output$value), ]
}

make_plots <- function(levels, rolling, metrics) {
  level_plot_data <- rbind(
    data.frame(
      quarter = levels$quarter,
      series = "Quarterly unemployment rate (%)",
      value = levels$unemployment_rate
    ),
    data.frame(
      quarter = levels$quarter,
      series = "Average weekly wage (USD)",
      value = levels$average_weekly_wage_usd
    )
  )

  transformed_plot_data <- rbind(
    data.frame(
      quarter = levels$quarter[-(1:4)],
      series = "Year-over-year unemployment change (percentage points)",
      value = diff(levels$unemployment_rate, lag = 4L)
    ),
    data.frame(
      quarter = levels$quarter[-(1:4)],
      series = "Year-over-year log wage growth",
      value = diff(log(levels$average_weekly_wage_usd), lag = 4L)
    )
  )

  forecast_plot_data <- rbind(
    data.frame(
      quarter = rolling$quarter,
      target = "Quarterly unemployment rate (%)",
      model = "Actual",
      value = rolling$actual_unemployment
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Quarterly unemployment rate (%)",
      model = "Seasonal naive",
      value = rolling$naive_unemployment
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Quarterly unemployment rate (%)",
      model = "Univariate SARMA",
      value = rolling$univariate_unemployment
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Quarterly unemployment rate (%)",
      model = "VAR",
      value = rolling$var_unemployment
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Average weekly wage (USD)",
      model = "Actual",
      value = rolling$actual_wage
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Average weekly wage (USD)",
      model = "Seasonal naive",
      value = rolling$naive_wage
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Average weekly wage (USD)",
      model = "Univariate SARMA",
      value = rolling$univariate_wage
    ),
    data.frame(
      quarter = rolling$quarter,
      target = "Average weekly wage (USD)",
      model = "VAR",
      value = rolling$var_wage
    )
  )

  list(
    levels = ggplot2::ggplot(
      level_plot_data,
      ggplot2::aes(x = quarter, y = value)
    ) +
      ggplot2::geom_line(linewidth = 0.55, colour = "#16697A") +
      ggplot2::facet_wrap(~series, scales = "free_y", ncol = 1L) +
      ggplot2::labs(x = NULL, y = NULL) +
      ggplot2::theme_minimal(base_size = 11),

    transformed = ggplot2::ggplot(
      transformed_plot_data,
      ggplot2::aes(x = quarter, y = value)
    ) +
      ggplot2::geom_hline(yintercept = 0, colour = "grey75") +
      ggplot2::geom_line(linewidth = 0.5, colour = "#489FB5") +
      ggplot2::facet_wrap(~series, scales = "free_y", ncol = 1L) +
      ggplot2::labs(x = NULL, y = NULL) +
      ggplot2::theme_minimal(base_size = 11),

    forecasts = ggplot2::ggplot(
      forecast_plot_data,
      ggplot2::aes(x = quarter, y = value, colour = model, linetype = model)
    ) +
      ggplot2::geom_line(linewidth = 0.65) +
      ggplot2::facet_wrap(~target, scales = "free_y", ncol = 1L) +
      ggplot2::scale_colour_manual(values = c(
        "Actual" = "#111111",
        "Seasonal naive" = "#888888",
        "Univariate SARMA" = "#16697A",
        "VAR" = "#E76F51"
      )) +
      ggplot2::labs(
        x = NULL,
        y = NULL,
        colour = NULL,
        linetype = NULL
      ) +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(legend.position = "bottom"),

    errors = ggplot2::ggplot(
      metrics[metrics$metric == "RMSE", ],
      ggplot2::aes(x = model, y = value, fill = model)
    ) +
      ggplot2::geom_col(width = 0.65, show.legend = FALSE) +
      ggplot2::facet_wrap(~target, scales = "free_y", ncol = 1L) +
      ggplot2::scale_fill_manual(values = c(
        "Seasonal naive" = "#888888",
        "Univariate SARMA" = "#16697A",
        "VAR" = "#E76F51"
      )) +
      ggplot2::labs(x = NULL, y = "Rolling one-step RMSE") +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 15, hjust = 1))
  )
}

run_portfolio_analysis <- function(project_root = ".", write_outputs = TRUE) {
  data_path <- file.path(
    project_root, "data", "processed", "houston_quarterly_aligned.csv"
  )
  metadata_path <- file.path(
    project_root, "data", "processed", "snapshot_metadata.csv"
  )
  if (!file.exists(data_path) || !file.exists(metadata_path)) {
    stop("Frozen data are missing. Run R/download_data.R from the project root.")
  }

  levels <- utils::read.csv(data_path, stringsAsFactors = FALSE)
  levels$quarter <- as.Date(levels$quarter)
  snapshot_metadata <- utils::read.csv(metadata_path, stringsAsFactors = FALSE)

  stopifnot(
    nrow(levels) >= 80L,
    !anyNA(levels),
    identical(max(levels$quarter), as.Date("2025-01-01")),
    all(levels$months_observed == 3L)
  )

  split_index <- floor(0.80 * nrow(levels))
  training_rows <- 5L:split_index
  delta_unemployment <- c(
    rep(NA_real_, 4L),
    diff(levels$unemployment_rate, lag = 4L)
  )
  wage_log_growth <- c(
    rep(NA_real_, 4L),
    diff(log(levels$average_weekly_wage_usd), lag = 4L)
  )

  unemployment_ranking <- rank_candidates(delta_unemployment[training_rows])
  wage_ranking <- rank_candidates(wage_log_growth[training_rows])
  unemployment_spec <- select_specification(unemployment_ranking)
  wage_spec <- select_specification(wage_ranking)
  unemployment_ranking$selected <- unemployment_ranking$model ==
    unemployment_spec$model
  wage_ranking$selected <- wage_ranking$model == wage_spec$model

  transformed_training <- data.frame(
    delta_unemployment = delta_unemployment[training_rows],
    wage_log_growth = wage_log_growth[training_rows]
  )
  var_lag <- select_var_lag(transformed_training, maximum = 4L)
  initial_var <- vars::VAR(transformed_training, p = var_lag, type = "const")
  maximum_var_root <- max(Mod(vars::roots(initial_var)))

  diagnostics <- rbind(
    model_diagnostics(
      delta_unemployment[training_rows],
      unemployment_spec,
      "Year-over-year change in unemployment"
    ),
    model_diagnostics(
      wage_log_growth[training_rows],
      wage_spec,
      "Year-over-year log wage growth"
    )
  )

  rolling <- rolling_evaluation(
    levels,
    split_index,
    unemployment_spec,
    wage_spec,
    var_lag
  )
  metrics <- forecast_metrics(rolling)
  tests <- stationarity_tests(levels)
  plots <- make_plots(levels, rolling, metrics)

  selection <- data.frame(
    component = c(
      "Unemployment univariate SARMA model",
      "Wage univariate SARMA model",
      "Univariate selection rule",
      "VAR lag",
      "Maximum VAR companion root modulus"
    ),
    selected_value = c(
      unemployment_spec$model,
      wage_spec$model,
      "Lowest training AICc among candidates passing a 12-lag Ljung-Box check at 5%",
      var_lag,
      sprintf("%.4f", maximum_var_root)
    ),
    stringsAsFactors = FALSE
  )

  analysis_metadata <- data.frame(
    field = c(
      "aligned_observations",
      "aligned_start",
      "aligned_end",
      "initial_training_end",
      "evaluation_start",
      "evaluation_end",
      "evaluation_quarters",
      "evaluation_design",
      "modelled_transformations",
      "naive_baseline"
    ),
    value = c(
      nrow(levels),
      quarter_label(min(levels$quarter)),
      quarter_label(max(levels$quarter)),
      quarter_label(levels$quarter[split_index]),
      quarter_label(levels$quarter[split_index + 1L]),
      quarter_label(max(levels$quarter)),
      nrow(rolling),
      "Expanding-window, one-quarter-ahead point forecasts",
      "Year-over-year unemployment change and year-over-year log wage growth",
      "Same quarter in the previous year"
    )
  )

  if (write_outputs) {
    results_dir <- file.path(project_root, "results")
    figures_dir <- file.path(project_root, "figures")
    dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)

    utils::write.csv(tests, file.path(results_dir, "stationarity_tests.csv"), row.names = FALSE)
    utils::write.csv(
      unemployment_ranking,
      file.path(results_dir, "candidate_models_unemployment.csv"),
      row.names = FALSE
    )
    utils::write.csv(
      wage_ranking,
      file.path(results_dir, "candidate_models_wage.csv"),
      row.names = FALSE
    )
    utils::write.csv(selection, file.path(results_dir, "model_selection.csv"), row.names = FALSE)
    utils::write.csv(diagnostics, file.path(results_dir, "residual_diagnostics.csv"), row.names = FALSE)
    utils::write.csv(metrics, file.path(results_dir, "forecast_metrics.csv"), row.names = FALSE)
    utils::write.csv(rolling, file.path(results_dir, "rolling_forecasts.csv"), row.names = FALSE)
    utils::write.csv(
      analysis_metadata,
      file.path(results_dir, "analysis_metadata.csv"),
      row.names = FALSE
    )
    capture.output(
      sessionInfo(),
      file = file.path(results_dir, "session-info.txt")
    )

    ggplot2::ggsave(
      file.path(figures_dir, "01_aligned_series.png"),
      plots$levels,
      width = 8.2,
      height = 6.2,
      dpi = 180
    )
    ggplot2::ggsave(
      file.path(figures_dir, "02_stationary_transformations.png"),
      plots$transformed,
      width = 8.2,
      height = 6.2,
      dpi = 180
    )
    ggplot2::ggsave(
      file.path(figures_dir, "03_rolling_forecasts.png"),
      plots$forecasts,
      width = 8.2,
      height = 6.5,
      dpi = 180
    )
    ggplot2::ggsave(
      file.path(figures_dir, "04_rmse_comparison.png"),
      plots$errors,
      width = 8.2,
      height = 6.2,
      dpi = 180
    )
  }

  list(
    levels = levels,
    snapshot_metadata = snapshot_metadata,
    analysis_metadata = analysis_metadata,
    split_index = split_index,
    stationarity = tests,
    unemployment_ranking = unemployment_ranking,
    wage_ranking = wage_ranking,
    unemployment_spec = unemployment_spec,
    wage_spec = wage_spec,
    var_lag = var_lag,
    maximum_var_root = maximum_var_root,
    diagnostics = diagnostics,
    rolling = rolling,
    metrics = metrics,
    plots = plots
  )
}
