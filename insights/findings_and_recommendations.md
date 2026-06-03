# Findings & Recommendations
### DESNZ Procurement Spend Analysis — Calendar Year 2024

This document presents the analytical findings from £12.03bn of DESNZ
departmental spending (6,047 transactions, 877 recipients), the methodology
behind them, and the actions a procurement team would take in response.

The dataset is UK public open data, but the questions are deliberately the ones
an energy business asks of its own procurement spend: where does
money concentrate, what drives its timing, and how much is competitive
procurement versus transfer?

---

## Methodology (how the numbers can be trusted)

Every figure below sits on a cleaning process that was profiled before it was
applied — the cleaning rules are evidence-based, not assumed:

- **Encoding.** The source files are not UTF-8 (latin-1); resolved at load so no
  rows were silently dropped.
- **Type integrity.** `Amount` arrived as text (thousand-separators); cast to
  numeric only after confirming every value converts cleanly — zero failures.
- **Completeness.** 8 of 18 columns were ~85.5% empty (an identical null count
  across them, pointing to a single non-populating record type). They were
  dropped: at that emptiness they cannot support reliable segmentation.
- **Duplicates — handled carefully.** Only rows identical across *all* fields
  were removed (3 rows). 159 transaction numbers carry multiple line items with
  different amounts; these are legitimate split payments and were **kept** — a
  naïve de-duplication on transaction ID would have erased real spend and
  understated the department's outlay.
- **No refunds/anomalies.** Zero non-positive amounts, so totals are clean.

This is the core discipline: the totals are defensible because the gaps,
duplicates, and type issues were measured and decided on explicitly.

---

## Finding 1 — Spend is highly concentrated, but in public bodies, not suppliers

**Evidence.** The top 10 recipients absorb **85.4%** of total spend; the top 50,
**92.6%**. Out of 877 recipients, a handful dominate:

| Recipient | Spend | Transactions |
|---|---:|---:|
| Nuclear Decommissioning Authority | £4.31bn | 35 |
| NNB Holding Company (Sizewell C) | £2.00bn | 14 |
| Ofgem | £1.30bn | 133 |
| Consolidated Fund Account | £0.70bn | 18 |
| National Grid Holdings One | £0.63bn | 1 |

**Interpretation.** In a normal procurement context, 85% with ten suppliers is a
red flag for over-dependence. Here it is **not** — the top recipients are
arm's-length bodies and major infrastructure programmes, so the concentration
reflects grant and capital transfer, not fragile reliance on a few vendors.
Reading the number without the context would produce the wrong conclusion.

**Recommendation.** Separate "transfer" spend (grants, equity, ALB funding) from
"operational procurement" before any concentration-risk assessment. The genuine
procurement-risk question lives in the operational tail, not the headline.

---

## Finding 2 — Two spending spikes, two different causes

**Evidence.** Monthly spend sits around £0.8–1.0bn for most of the year, with two
clear peaks: **March (£1.55bn)** and **September (£1.51bn)**. Critically, March
has a high transaction count (807) while September has the **lowest of any month
(409)**.

**Interpretation.** March is the classic UK fiscal year-end surge — broad-based
spending before budgets reset. September is the opposite shape: few transactions,
very high value, i.e. a small number of large lumpy capital payments. Same spend
height, completely different driver — visible only by reading spend **and**
volume together, not spend alone.

**Recommendation.** Treat the two peaks differently. Year-end surges are a budget-
management and forecasting issue (smooth commitment across the year); large lumpy
months are a cash-flow and approval-control issue (ensure big-ticket payments
have proportionate oversight).

---

## Finding 3 — The spend-type mix is more balanced than the recipient table implies

**Evidence.** By recipient type, spend splits **68% Vendor (£8.24bn) / 21% Grant
(£2.50bn) / 11% WGA-only (£1.29bn)**. The largest expense categories are
Grant-in-aid to ALBs (£4.64bn) and equity/capital-grant lines.

**Interpretation.** The top *recipients* are public bodies, yet two-thirds of
spend is classified as Vendor — so a substantial competitive-procurement layer
exists beneath the headline transfers. The two views (recipient vs. type) tell
different stories, and both are needed for an accurate picture.

**Recommendation.** Analyse procurement performance on the Vendor segment
specifically; assess the Grant/WGA segments as policy/transfer rather than
sourcing. Blending them distorts both.

---

## Limitations

- One calendar year only — trends are within-year, not year-over-year.
- The £25k threshold excludes smaller transactions; the long tail of
  lower-value procurement is not captured here.
- Some expense types are accounting movements (e.g. cash transfers to Treasury)
  rather than purchases; flagged, not removed.
- Recipient names were standardised; residual minor naming variants may persist
  below the level tested.

---

## One-line summary

DESNZ's 2024 spend looks dangerously concentrated and erratically timed — until
the data-quality and segmentation work shows it is mostly orderly public-sector
transfer, with the real procurement signal sitting in the vendor segment beneath
the headlines.