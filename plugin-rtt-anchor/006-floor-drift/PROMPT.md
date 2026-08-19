# Design prompt: 006-floor-drift

Does the path's true floor move over time — and how quickly does a measurement
go stale?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. Deliverable: a draft `RUN.md` (per
`../../TEMPLATE/RUN.md`) plus an analysis plan, for John's review. Do not run
anything against any host.

## The question

§1.4 of the plugin's `docs/open-questions.md`. The minimum over a window is
only meaningful if the true floor is stable across that window: routing
changes, diurnal congestion, and maintenance windows can all move it, and a
millisecond of floor movement reads as ~150 km of apparent movement from a
machine that never moved. The question sets the maximum useful window length
and how often evidence must be refreshed.

## John's directive (design to this, not to §1.4's one-week sketch)

The intended shape is a **standing process, not a one-off run**: ongoing
regular slow background sampling, treated as a time series, with **random
subsampling to simulate a verifier arriving at an arbitrary moment**. §1.4's
"20 pairs every 15 minutes for a week" is a starting sketch to be interrogated
— the sampling rate, window size, and duration are design questions, and
"ongoing" changes several things a batch run would not face.

## What we know (with sources)

- Topology as in 004: attester `hap-gpu` → anchor `hap-server`
  (`../infra/README.md`); anchor deployment is a prerequisite shared with 004.
- The attester can run continuously (`-count 0`); default `-interval` is 30 s.
  At the anchor's default `-verify-interval` of 29 s, a slow continuous rate is
  the one shape the production rate limit already tolerates.
- Shared-machine rules for a standing process on `hap-gpu`: named tmux session,
  logs under `~/johnx/`, nothing orphaned (`../infra/hap-cluster.md`). A
  standing process should also survive reboots or at least fail loudly —
  design the supervision honestly (tmux vs systemd --user vs cron; the box is
  not ours to install system units on without asking).
- Repo conventions say raw captures are committed under `data/`. An unbounded
  ongoing capture strains that convention: design the commit cadence, file
  rotation, and size expectations explicitly (JSONL with `-raw` runs a few MB
  per 10,000 records) rather than letting the working tree rot.

## What we assume (unverified)

- That per-window minima are the right unit for the time series, and that
  window length can be chosen once — it may itself be the parameter under
  study.
- That the analysis is standard time-series work. Which methods are actually
  appropriate for the *minimum* of a heavy-one-sided-noise process over time
  (changepoint detection for route changes? seasonal decomposition for diurnal
  structure?) needs investigation — flag for deeper treatment rather than
  committing casually.

## What we don't know

- How staleness should map to evidence weight — that is analysis/semantics
  work downstream of the data, and this experiment should collect what that
  future analysis will need (which argues for keeping raw per-probe records,
  not just window minima).
- Whether the anchor end (1 vCPU, other duties) contributes drift of its own,
  and how we would distinguish anchor-side drift from path drift. Possibly
  unanswerable with one anchor; say so if so.
- Interaction with other experiments sharing the path and anchor (004, 005
  bursts punching through while this trickles): does concurrent burst traffic
  contaminate the background series, and should the runner pause during
  bursts? Needs a coordination rule.
