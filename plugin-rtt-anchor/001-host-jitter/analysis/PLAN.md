# Analysis plan: 001-host-jitter

**Draft for review, written before any data exists.** Fixed now so the
analysis cannot drift toward whatever the data happens to support. Everything
here computes from the raw JSONL and snapshots under `data/`; scripts live in
this directory, are deterministic (fixed bootstrap seed), and re-run from
scratch. Conclusions go to `REPORT.md`, not here.

## Inputs

- `data/<cell>.jsonl` — one observation per line. Primary variable:
  `anchor_measured_rtt_ns`. Secondary: `attester_measured_rtt_ns` (the min of
  the attester's two self-timed RTTs), `challenged`, validity flags, `seq`,
  `error`.
- `data/<cell>-{pre,post}.snapshot.txt` — host state.
- `data/<cell>-*.stderr.log` — `gctrace` lines with wall-clock-ordered GC
  pauses.
- If the export branch landed (see RUN.md, Proposed plugin changes):
  `attester_rtt0_ns`, `attester_rtt1_ns`, `attester_turnaround_ns`, and
  nanosecond timestamps. Analyses marked **[branch]** below activate only in
  that case.

## Pass 0 — validation, before any statistics

1. Line counts per cell: 5,000 expected; every shortfall accounted for.
2. Error lines counted per cell → loss/timeout rate. These are results (loss
   under load), not exclusions to hide.
3. Flag consistency: challenged cells must show `challenged: true`,
   `reply0_valid`, `reply1_valid`, `anchor_key_match` all true; unchallenged
   cells `challenged: false`. Any violation quarantines the cell for
   investigation.
4. **Wraparound screen.** A backward clock step between the anchor's two
   stamps wraps the interval to a near-2^64 value (RUN.md, Clock domains).
   Any observation above 10^12 ns (1,000 s — physically impossible here) is
   tallied separately as a clock artifact, reported, and excluded from
   distribution statistics. The count itself is a finding about clock
   discipline.
5. Zero screen: `anchor_measured_rtt_ns == 0` should be impossible for a real
   pair; count and investigate any occurrence.
6. Snapshot diff per cell: governor changed, load average grossly off the
   cell's nominal condition, foreign processes appeared — the cell is flagged
   "contaminated" and reported with that label rather than silently pooled.
7. Warm-up rule: first 50 pairs per cell excluded from all summary statistics
   (pre-registered in RUN.md). Sensitivity check: recompute the headline
   table with no exclusion; if any statistic moves by more than its bootstrap
   CI, say so in the report.

## Pass 1 — per-cell distributions

For each cell, on `anchor_measured_rtt_ns` in microseconds:

- Summary table: min, p1, p5, p25, p50, p75, p90, p99, p99.9, max, mean, SD,
  and the fraction of pairs exceeding 1 ms. Bootstrap 95% CIs (10,000
  resamples, fixed seed) on min, p1, p50, p99, p99.9.
- Plots: histogram (linear and log-x); empirical CCDF on log-log axes (the
  tail's shape is the point — power-law-ish versus exponential decides how
  minima and quantiles behave); time-series strip of value against `seq`
  (stationarity, warm-up, foreign-load episodes); block minima (min per
  consecutive 500 pairs, 10 blocks per cell) to show floor stability within a
  cell; lag-1 through lag-50 autocorrelation of the series.

## Pass 2 — is min-over-burst justified here? (pre-registered decision rule)

The brief questions whether the minimum is the right summary on a
zero-baseline run, and the code trace sharpened the question: every
mechanical noise term enters additively (one-sided), but the interval is a
wall-clock difference across differently-sourced stamps, so clock slew adds a
small two-sided term (~0.1 µs scale) and clock steps add rare catastrophic
ones. On a software floor there is also no physical constant for the minimum
to converge *to* — the floor itself is the quantity under study, and the
sample minimum estimates an extreme quantile with high variance.

Decision rule, fixed in advance:

1. **Primary floor statistic: p1**, with bootstrap CI. It is stable under
   sample size, robust to the two-sided clock terms, and still sits on the
   distribution's left edge.
2. **Min is always reported alongside**, with its own bootstrap CI and a
   subsample-min curve: distribution of min(N) for N = 10, 50, 100, 500,
   1,000, 5,000 drawn by bootstrap from the cell. This is also the
   zero-baseline analogue of 004's convergence question and should be
   directly comparable to 004's curve later.
3. **Sharp-edge check:** if (p1 − min) < 0.1 × (p50 − min), the left edge is
   sharp and min and p1 tell the same story — report both, and minima from
   this pipeline may be interpreted as "the floor." If the edge is diffuse,
   the report must say the software floor is not a hard edge and
   minimum-based reasoning inherits that softness. Either outcome is a
   result.
4. Falsifier for the one-sidedness assumption itself: any negative-delta
   evidence — wraparound artifacts (Pass 0.4), or **[branch]** anchor
   interval minus attester turnaround coming out negative — caps how sharp
   the floor claim is allowed to be.

## Pass 3 — contrasts

Each contrast compares full distributions (overlaid ECCDFs and QQ plots), not
just one number. Headline deltas are quoted at p1, p50, and p99 with
bootstrap CIs on the difference.

1. **Challenge delta** (cells 1 vs 8 at idle; 6 vs 9 under full load).
   Expected from the trace: the delta window contains reply-0 unmarshal +
   cmsg parse + nonce extract + probe build + **Ed25519 sign** + marshal
   (RUN.md, The unchallenged contrast). Prior: roughly 92 µs of median on a
   different machine (plugin `docs/protocol.md`) — a hint, not a target.
   Design intent for later reconciliation with 002: 002 measures isolated
   sign/verify distributions on the same host and commit; the challenge
   delta here should be approximately 002's sign cost plus parsing overhead.
   If the delta is materially *smaller* than 002's isolated signing cost,
   something in the trace or in 002's method is wrong — that contradiction
   is a finding to chase, not to average away.
   Complication to check: if the delta differs between idle and loaded cells
   beyond CI, the challenge cost is load-dependent and calibrating it away
   as a constant `-processing-delay` is not sound.
2. **Load effect** (1 → 4 → 6 unpinned; 2 → 5 → 7 pinned-separate).
   Prior from the sleep-overshoot proxy (`../infra/README.md`): floor
   insensitive to load, tail unpredictable. Both parts are falsifiable here:
   the floor claim dies if p1 moves beyond CI across load levels; the tail
   claim is quantified by how p99/p99.9 move. Loss rate per load level is
   part of this contrast.
3. **Pinning effect** (1 vs 2 vs 3 at idle; 4 vs 5, 6 vs 7 under load).
   Same-core (cell 3) is the coarse decomposition axis and the stand-in for
   the single-vCPU situation: if same-core inflates the distribution the way
   cell 10 (hap-server) is inflated relative to hap-gpu, contention explains
   the hap-server contrast without invoking KVM or hardware differences.
   If pinning-separate under load (7) rescues the tail relative to unpinned
   under load (6), pinning is the cheap accuracy win §1.3 hypothesized.
4. **Replication check** (rep A vs rep B, all hap-gpu cells). Any statistic
   whose A/B difference exceeds its bootstrap CI marks day-to-day
   non-stationarity; the report then presents per-rep numbers, never pooled
   ones.
5. **hap-server contrast** (10, 11 vs 1, 8). Reported as an upper bound for
   the production anchor host only, with the contention-by-construction
   caveat stated wherever the number appears.

## Pass 4 — mechanism checks

1. **GC attribution.** Cross-reference tail excursions (observations above
   p99) against `gctrace` pause timestamps in the stderr logs. Coarse without
   nanosecond observation timestamps (the pinned binary stamps at 1 s
   resolution — RUN.md, What the JSONL exports today); **[branch]** exact
   with them. Outcome either implicates GC in the tail or retires it.
2. **Attester/anchor cross-check.** Per pair, `attester_measured_rtt_ns`
   (min of RTT0/RTT1) covers complementary windows to the anchor's interval
   — RTT0 contains the anchor's turnaround, the anchor's interval contains
   the attester's. Scatter and rank-correlate the two per cell: strong
   correlation under load says one shared cause (the scheduler) moves both;
   weak correlation says the two processes' costs fluctuate independently.
3. **[branch] Decomposition.** Per pair:
   `residue = anchor_measured_rtt_ns − attester_turnaround_ns` — the anchor
   send path plus both kernel loopback deliveries. Distributions of
   turnaround and residue per cell; which one the load and pinning effects
   act on; negative residues (should be impossible barring clock artifacts)
   feed Pass 2.4.
4. **Spacing sanity.** If lag autocorrelation at 100 ms spacing (Pass 1) is
   materially nonzero, the effective sample size is below N and every
   bootstrap CI here is optimistic — flag it, report effective N via the
   autocorrelation-adjusted formula, and hand the thread to 005.

## What would falsify or complicate each intended conclusion

| Intended conclusion | Falsified or complicated by |
|---|---|
| "The machinery floor on a quiet bare-metal host is X µs" | Rep A/B disagreement beyond CI; diffuse left edge (Pass 2.3); governor or foreign-load contamination in snapshots; wraparound count > 0 near the floor |
| "The challenge costs Y µs" | Load-dependence of the delta (then it is a function, not a number); inconsistency with 002's isolated signing cost |
| "Load moves the tail, not the floor" | p1 shifting with load beyond CI (floor claim dies); or the tail *not* moving under 24-core saturation (then synthetic load is too weak a proxy to conclude anything, and the claim is untested rather than confirmed) |
| "Pinning is the cheap accuracy win" | No tail improvement in cells 5/7 vs 4/6; or improvement that vanishes at rep B |
| "Min-over-burst is a sound summary for zero-baseline runs" | Pass 2's decision rule going the other way; any Pass 2.4 negative-delta evidence |
| "These numbers bound the host term of the cross-host error budget" | The loopback-vs-NIC timestamping assumption failing (open caveat in RUN.md); this conclusion must always carry that caveat until 003 or a kernel-source check retires it |

## Non-goals

No conversion to meters (the program README's 150 m/µs orientation is for
readers; deliverables here are microseconds). No pooling across hosts. No
longitudinal claims — 20 cells over two days characterize a floor, not its
drift; that is 006. No estimate of what real training load does — that is
008, and nothing here should be quoted as if it covered it.

## Tooling

Python scripts in this directory, driven by a single entry point
(`make` or `run.sh`) that takes `data/` and emits `figures/` and
`tables/` deterministically. Dependencies pinned in a lockfile committed
alongside. Analysis runs on the analyst's machine, never on the testbed
hosts.
