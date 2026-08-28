# Data provenance and alignment

This project uses two FRED series ultimately sourced from the U.S. Bureau of
Labor Statistics.

| Series | Meaning | Native frequency | Unit |
|---|---|---|---|
| [`HOUS448URN`](https://fred.stlouisfed.org/series/HOUS448URN) | Unemployment rate in Houston–The Woodlands–Sugar Land, TX (MSA) | Monthly | Percent, not seasonally adjusted |
| [`ENUC264240010`](https://fred.stlouisfed.org/series/ENUC264240010) | Average weekly wages for employees in covered establishments in Houston–Sugar Land–Baytown, TX (MSA) | Quarterly | Dollars per week, not seasonally adjusted |

The source pages tag these BLS-derived series as public-domain data with a
citation requested. The repository retains the series identifiers and direct
links so users can review the current notes and citations.

## Frozen snapshot

`R/download_data.R` downloads the FRED CSV endpoints and retains observations
through a fixed analysis cutoff of 2025 Q1. It computes each quarterly
unemployment observation as the arithmetic mean of all three monthly rates,
drops incomplete quarters, and inner-joins the wage observation for the same
quarter. The resulting `data/processed/houston_quarterly_aligned.csv` contains
141 consecutive quarters from 1990 Q1 through 2025 Q1.

The raw and processed snapshots are committed so later revisions to source data
do not silently change the portfolio result. `snapshot_metadata.csv` records the
retrieval timestamp, cutoff, source IDs, aggregation rule, range, and row count.

## Caveats

- FRED observations can be revised; a refreshed download may differ from the
  committed snapshot even with the same cutoff.
- Both series are not seasonally adjusted.
- Their titles use different historical names for the Houston metropolitan
  area. This project treats them as the intended regional pair but does not
  claim that geographic definitions stayed perfectly constant through time.
- Average weekly wages are not a statutory minimum wage and do not measure the
  wage of a typical individual worker.
