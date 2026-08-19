# Design prompt: 004-burst-convergence

How many probes does a burst need before the minimum stops improving — and
where is the knee that sets the operating point for everything downstream?

This is a design brief, not a design. This directory already contains a
`RUN.md` drafted for an earlier topology (Hetzner server pair) before the
experiment numbering was re-baselined; treat it as source material to be
redrafted, not as settled method. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. Deliverable: a redrafted `RUN.md` for the
current topology plus an analysis plan, for John's review. Do not run anything
against any host.

## The question

§1.1 of the plugin's `docs/open-questions.md` — the load-bearing question of
the phase. The estimator is min over a burst because network noise is
one-sided; what is unknown is the *rate* of convergence, which converts probes,
seconds, and CPU into bound tightness. The proposed shape: one large capture
over the real path, subsampled into every burst size, so the convergence curve
comes from data rather than repeated runs.

## What we know (with sources)

- Topology: attester on `hap-gpu` (Cambridge), anchor on `hap-server`
  (Hetzner Helsinki, `37.27.183.180`). Ground truth: 1,768 km great-circle,
  ICMP min 38.001 ms, unusually tight spread (max−min < 1 ms over 20 probes) —
  `../infra/README.md`. The anchor is NOT yet deployed on `hap-server`;
  deployment (binary, key, allowlist, `ufw allow 8924/udp`, systemd unit) is
  part of this experiment's runbook. `hap-server` has a single vCPU.
- The old draft's method sketch: 10,000 pairs at fixed 20 ms spacing,
  `-verify-interval 10ms` on the anchor, repeated at three times of day,
  bootstrap-subsampled at N = 1…500. All of it is challengeable — especially
  whether 10,000 and 20 ms are right, and whether three times of day is enough
  to say anything about load dependence.
- The field to analyze is `anchor_measured_rtt_ns` (signed, verifier-grade);
  `attester_measured_rtt_ns` is a self-reported sanity check. Capture with
  `-json -raw` always — the raw signed bytes are the evidence.
- The reverse direction is not available: `hap-gpu` is behind NAT and cannot
  be an anchor from the WAN. The old draft's "run both directions" does not
  survive the topology change; note it as a limitation.
- Results are read against 001 (host floor) and 003 (local segment): the burst
  minimum should not be able to beat host floor + local segment + propagation.
  Design the validation checks (rate-limit throttling visible as gaps in
  timestamps; `reply0_valid`/`reply1_valid`/`anchor_key_match` all true).
- `-interval` in the attester is a sleep *after* each pair, not a period —
  realized spacing must be computed from the JSONL, not assumed from the flag
  (`cmd/attester/main.go`).

## What we assume (unverified)

- The power-law-tail model in §1.1 (excess of min(N) falling as N^(−1/α)) is a
  hypothesis to test against the data, not a fact to build the analysis on.
  Design the analysis so it can reject that shape.
- That bootstrap subsampling from one capture is statistically equivalent to
  independent bursts of size N. It is not, exactly — samples within the capture
  share the capture's hour and any autocorrelation (005's subject). State the
  limitation and design around it where cheap (e.g. block bootstrap; needs
  investigation).

## What we don't know

- Whether the convergence rate is load/time-of-day dependent, and what
  repetition schedule would establish that honestly rather than suggestively.
- What burst size the 1-vCPU anchor can absorb at 20 ms (or tighter) spacing
  before the anchor itself becomes the bottleneck — the anchor's turnaround is
  inside the measured window too.
- How to fold in the timestamp-source analysis once the plugin exports both
  receive stamps (see `../README.md`, the unslotted questions).
