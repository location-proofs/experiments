# Design prompt: 005-burst-spacing

Does the spacing of probes within a burst change what the burst teaches you —
and what is the effective sample size at each spacing?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. Deliverable: a draft `RUN.md` (per
`../../TEMPLATE/RUN.md`) plus an analysis plan, for John's review. Do not run
anything against any host.

## The question

§1.2 of the plugin's `docs/open-questions.md`. Fifty probes 20 ms apart and
fifty probes 2 s apart cost the same but sample the network differently: a
tight burst shares routing state, queue occupancy, and possibly a scheduling
quantum on both hosts, so its samples are correlated and the effective sample
size is smaller than N. There is also a self-interference risk — a tight burst
can queue behind itself. The deliverable §1.2 names is the effective sample
size per spacing, which decides whether "answer in one second" and "answer
well" are compatible. This also feeds back into how 004's convergence curve
(measured at one fixed spacing) should be read.

## What we know (with sources)

- §1.2's sketch: fix N = 50, sweep inter-probe spacing across 1 ms, 5 ms,
  20 ms, 100 ms, 1 s; compare min(50) distributions and estimate the
  autocorrelation of consecutive samples at each spacing. All challengeable —
  including whether N = 50 is the right fixed point and whether these five
  spacings bracket the interesting region.
- `-interval` is a sleep after each pair completes, so realized spacing =
  interval + pair duration (which includes a WAN round trip). At 1 ms nominal
  spacing over a 38 ms path this matters enormously — the design must either
  compute realized spacing from JSONL timestamps or reconsider whether the
  attester as-is can even produce a 1 ms spacing (needs investigation; may
  require concurrent pairs, which the current single-socket sender may not
  support — check `internal/signed/sender_linux.go`).
- The anchor rate limit must accommodate the tightest leg
  (`-verify-interval` below the smallest spacing), on a 1-vCPU anchor.
- Topology and ground truth as in 004 (`../infra/README.md`).

## What we assume (unverified)

- That autocorrelation of consecutive RTT samples is the right lens for
  effective sample size of a *minimum* statistic. Minima are order statistics;
  standard effective-N corrections are built for means. What the right
  statistical treatment is here genuinely needs investigation — flag it for
  the "week with a strong engineer" treatment rather than resolving it by fiat.
- That diurnal load variation can be decorrelated from the spacing sweep by
  interleaving repetitions. Design the interleaving explicitly.

## What we don't know

- Whether tight bursts self-interfere on this path (queueing behind our own
  packets) and how we would detect that signature in the data.
- Whether spacing interacts with the anchor's per-sender state or rate
  limiting in ways that contaminate the comparison (`reflector_linux.go`).
- How results here should revise 004's operating point — design the report so
  that revision is mechanical rather than interpretive.
