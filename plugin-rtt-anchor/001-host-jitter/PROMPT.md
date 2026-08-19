# Design prompt: 001-host-jitter

When the network is removed, what does our measurement pipeline report, and how
does that change when the machine is busy?

This is a design brief, not a design. You are asked to *develop* this
experiment's method, skeptically. Everything below is reviewable: challenge the
framing where it is wrong, separate what is known from what is assumed, and
where a question needs real investigation rather than a design decision, write
"needs investigation" instead of inventing an answer. Overconfident method text
is worse than an honest gap. The deliverable is a draft `RUN.md` (per
`../../TEMPLATE/RUN.md` and the conventions in the repo root `README.md`) plus
an analysis plan, for John's review. Do not run anything against any host.

## Background: what the anchor measures

One measurement is two request/response exchanges over UDP; the packets are
numbered 0 and 1. The attester sends a signed hello (probe 0). The anchor
replies (reply 0) carrying a fresh random nonce, and starts its stopwatch as
that reply leaves. The attester parses reply 0, copies the nonce into probe 1,
signs it, and sends it; the anchor stops the stopwatch when probe 1 arrives.
That interval — signed by the anchor, reported as `anchor_measured_rtt_ns` in
the attester's JSONL — is the only number a verifier can rely on. Because the
nonce is unpredictable, probe 1 cannot be prepared in advance, so the window
necessarily contains a real round trip plus the attester's processing. Full
detail: `../README.md` and the plugin's `docs/protocol.md`.

## The question

Run the anchor and the attester on the same machine, communicating over
loopback, so the true distance is zero and propagation time is approximately
zero. Whatever interval the anchor then reports is the cost of our own
machinery: scheduler wake-ups, kernel/userspace crossings, parsing, signing,
timestamping. Borrowing a term from GNSS receiver testing, this is a
**zero-baseline** run — the instrument measured against itself, with distance
removed — and what it characterizes is the instrument's **self-noise**: its
floor, its tail, and its sensitivity to load. It aims to settle §1.3 of the
plugin's `docs/open-questions.md`.

Two scoping points that must survive into the RUN.md:

- **The reported interval sums two processes' costs.** Between the anchor's two
  stopwatch clicks sit the anchor's own send path, the attester's entire
  turnaround (wake, parse, sign, send), and the anchor's receive path. A single
  number cannot say which side contributed what. Decomposing it as far as the
  instrumentation allows is a core design task — see "What we don't know."
- **Loopback packets never touch the network card.** The kernel turns them
  around internally, so this experiment does not measure NIC, driver, or
  interrupt costs; those belong to 003-local-segment. Say so in the RUN.md so
  nobody over-reads the result. (In the same vocabulary: a future run between
  two machines inside one datacenter would be a *short-baseline* test, and is
  not this experiment.)

## What we know (with sources)

- **Two prior hints exist; neither is committed evidence.** First, on a
  different machine (a commodity VPS), this same anchor-and-attester-on-one-host
  setup reported a median interval of 186 µs with the nonce challenge on and
  94 µs with it off (plugin `docs/protocol.md`) — so expect the machinery cost
  to be on the order of 100–200 µs, with the challenge roughly doubling it.
  Second, on the old Hetzner pair we ran a crude proxy: ask the OS to sleep
  1 ms, 500 times, and record the oversleep, which is scheduler delay. The
  oversleep floor was 20–32 µs, about 1% of sleeps overshot by more than a full
  millisecond, and how busy the machine was did not predict that tail
  (`../infra/README.md`). No raw data was committed behind either number; this
  experiment supersedes both properly.
- **Implementation facts that shape the measurement** (plugin source:
  `internal/signed/sender_linux.go`; each verified against the code, each with
  the reason it matters):
  - The attester busy-polls for up to 15 ms while waiting for each reply,
    spinning on a locked OS thread rather than sleeping. Its wake-up cost is
    therefore far lower than a sleeping process would pay — and it competes for
    a core the whole time, which changes what "under load" means.
  - It requires kernel receive timestamps (`SO_TIMESTAMPNS`) and exits without
    them, so arrival stamps are taken by the kernel at packet delivery, not by
    userspace after scheduling.
  - For its own log it prefers the kernel arrival stamp and falls back to a
    userspace clock read (`decideRTT`); the anchor's signed interval is
    unaffected by this choice.
  - The anchor rate-limits to one probe pair per `-verify-interval`, default
    29 s. This is a flag, not a constraint: lower it for bursts and record the
    value used. More broadly, we control both binaries — if a plugin default or
    a missing export blocks the right measurement, proposing a change (on a
    branch, recorded in the RUN.md) is in scope for this design.
- **The host**: `hap-gpu`, bare-metal Threadripper PRO 3945WX (12c/24t), five
  RTX 3090s power-capped to 200 W, a shared machine with social conventions
  that bind (announce load experiments beforehand, work under `~/johnx/`,
  named tmux, pin GPUs with CUDA_VISIBLE_DEVICES): `../infra/hap-cluster.md`.
- **A contrast run on `hap-server` (1 vCPU) would be contention-inflated by
  construction** — anchor and attester would share one core while the attester
  busy-polls. Decide whether that contrast is worth collecting and say what it
  would and would not mean.
- **Deliverables are stated in time, not distance.** For orientation, 1 µs of
  delay reads as roughly 150 m at half the speed of light — but converting to
  metres is downstream analysis, not this experiment's output. Report
  microseconds.

## What we assume (unverified)

- That loopback `SO_TIMESTAMPNS` timestamps behave comparably to NIC-path
  timestamps. Needs investigation or an explicit caveat.
- That synthetic CPU load disturbs the timing path the way real work does.
  Probably false in interesting ways: the easy synthetic load is `stress-ng`
  (a tool that spins CPU cores), but the real load on this machine is GPU
  training, which stresses different things — CPU-side dataloader threads,
  interrupt traffic from PCIe transfers, memory bandwidth. Treat load *type*
  as its own experimental axis (idle / synthetic CPU load / real training
  load, steppable across 1–5 GPUs) and say plainly what synthetic load does
  and does not represent. Document as an open question how far any load result
  generalizes across hardware and operating systems.
- That the minimum over a burst is the right summary statistic here. On a
  network path the minimum is justified because delay noise is one-sided —
  queueing, scheduling, and routing only ever add time — so the smallest of N
  samples converges on the true floor from above. On a zero-baseline run the
  floor is software, not physics, and that justification is shakier: for
  example, jitter in where the anchor's send timestamp is taken relative to
  when the packet actually moves could shift the measured interval in either
  direction. Check the distribution's shape before assuming the minimum means
  anything.

## What we don't know

- **The run plan — your main design task.** Which combinations of conditions to
  run (load level and type, challenge on/off, CPU pinning of the two
  processes), how many probe pairs per combination, how the pairs are spaced,
  and how many repetitions — enough to be statistically meaningful without
  being wasteful.
- **Whether the reported interval can be decomposed into anchor-side and
  attester-side costs.** The attester takes its own timestamps, and its view of
  "reply 0 arrived → probe 1 sent" is exactly its own turnaround; subtracting
  that from the anchor's interval would leave the anchor-side cost. Whether the
  attester's JSONL currently exports the fields that subtraction needs requires
  investigation; if it does not, the export change is worth proposing, and
  until it lands the RUN.md must present the number as a combined cost.
  Pinning the two processes to the same core versus different cores is a
  coarser decomposition axis available today.
- **Whether CPU frequency scaling or governor state moves the floor.** At
  minimum, snapshot host state — governor, frequency, load averages, anything
  else that could plausibly move timing — immediately before and after every
  capture, so a drifting host cannot silently contaminate a run.
- **How the challenged/unchallenged difference here reconciles with
  002-signature-cost's isolated numbers.** Design the capture so that
  reconciliation is possible later.

## Also wanted from this design

Trace the nonce's actual path through both binaries
(`~/code/plugin-rtt-anchor`: `internal/signed/sender_linux.go`,
`reflector_linux.go`, `cmd/attester/main.go`) — receive, parse, sign, send on
the attester side, and, crucially, where the anchor takes each of its two
stopwatch timestamps — and include it as a background section in the RUN.md.
Neither John nor anyone else should have to reason about an untraced path. A
diagram of this trace is separately wanted; your written trace is its source
material.
