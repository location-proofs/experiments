# Design prompt: 001-host-jitter

When the network is removed, what does our measurement pipeline report — and
how does that move when the machine is busy?

This is a design brief, not a design. You are asked to *develop* this
experiment's method, skeptically. Everything below is reviewable: challenge the
framing where it is wrong, separate what is known from what is assumed, and
where a question needs real investigation rather than a design decision, write
"needs investigation" instead of inventing an answer. Overconfident method text
is worse than an honest gap. The deliverable is a draft `RUN.md` (per
`../../TEMPLATE/RUN.md` and the conventions in the repo root `README.md`) plus
an analysis plan, for John's review. Do not run anything against any host.

## The question

Run the anchor and the attester on the same machine, over loopback, so
propagation is approximately zero. Whatever RTT the anchor then reports is the
cost of our own machinery — scheduler wake-up, kernel/userspace crossings,
parsing, signing. This experiment classifies that error source: its floor, its
tail, and its sensitivity to load. It aims to settle §1.3 of the plugin's
`docs/open-questions.md`.

## What we know (with sources)

- The protocol and the field to analyze: the anchor times its own reply-0-tx to
  probe-1-rx and signs the interval (`anchor_measured_rtt_ns` in the attester's
  JSONL). See `../README.md` and the plugin's `docs/protocol.md`.
- Loopback packets never touch the NIC — they turn around inside the kernel.
  So this experiment does NOT measure NIC/driver/interrupt costs; those belong
  to 003-local-segment. Say so in the RUN.md so nobody over-reads the result.
- A previous loopback measurement on different hardware: challenged median
  186 µs vs unchallenged 94 µs (plugin `docs/protocol.md`). A sleep-overshoot
  proxy on the old Hetzner pair showed floors of 20–32 µs with p99 above 1 ms,
  and load did not predict the tail (`../infra/README.md` — note that table has
  no committed raw data behind it; this experiment supersedes it properly).
- Implementation details that shape what you are measuring: the sender locks
  its OS thread, busy-polls for up to 15 ms per pair, requires SO_TIMESTAMPNS
  (exits without it), and collapses kernel/userspace receive stamps via
  `decideRTT` (plugin source: `internal/signed/sender_linux.go`). The anchor's
  default rate limit (`-verify-interval` 29 s) must be lowered for bursts.
- The host: `hap-gpu`, bare-metal Threadripper PRO 3945WX (12c/24t), five
  RTX 3090s power-capped to 200 W, a shared machine with social conventions
  that bind (announce load experiments beforehand, work under `~/johnx/`,
  named tmux, pin GPUs with CUDA_VISIBLE_DEVICES): `../infra/hap-cluster.md`.
- A contrast run on `hap-server` (1 vCPU) would be contention-inflated by
  construction — anchor and attester share one core there. Decide whether that
  contrast is worth collecting and say what it would and would not mean.
- 1 µs ≈ 150 m at c/2. Deliverables should be stated in both units.

## What we assume (unverified)

- That loopback SO_TIMESTAMPNS timestamps behave comparably to NIC-path
  timestamps. Needs investigation or an explicit caveat.
- That `stress-ng` CPU load and a real training job stress the relevant
  resources similarly. Probably false in interesting ways (dataloader threads,
  PCIe interrupts, memory bandwidth); the condition design should treat "GPU
  training load" as its own axis, steppable across 1–5 GPUs, and be honest
  about what synthetic load does and does not represent.
- That the minimum over a burst suppresses tail noise here as it does on a
  network path. Loopback noise may not be one-sided in the same way.

## What we don't know

- The condition matrix, pair counts, spacing, and repetitions that make this
  statistically meaningful without being wasteful — your main design task.
- Whether CPU frequency scaling / governor state moves the floor. Worth
  recording at minimum (see harness conventions in the phase plan: snapshot
  host state before and after every capture).
- How often the challenged/unchallenged difference here reconciles with
  002-signature-cost's isolated numbers — design the capture so that
  reconciliation is possible later.

## Also wanted from this design

Trace the nonce's actual path through the attester code
(`~/code/plugin-rtt-anchor`: `internal/signed/sender_linux.go`,
`reflector_linux.go`, `cmd/attester/main.go`) — receive, parse, sign, send,
with where each timestamp is taken — and include it as a background section in
the RUN.md. Neither John nor anyone else should have to reason about an
untraced path. A diagram of this trace is separately wanted; your written trace
is its source material.
