# Design prompt: 002-signature-cost

What does Ed25519 signing and verification cost, as a distribution, at exactly
the sizes this protocol signs — and does that cost account for what 001 sees?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. The deliverable is a draft `RUN.md` (per
`../../TEMPLATE/RUN.md`, repo conventions in the root `README.md`) plus a
benchmark harness design and analysis plan, for John's review. Do not run
anything against any host.

## The question

Signing happens inside the anchor-measured window (the attester signs the nonce
echo before the anchor's clock stops), so signature cost converts into apparent
distance at roughly 150 m/µs. §2.1 of the plugin's `docs/open-questions.md`
asks what each scheme costs in metres; this experiment establishes the Ed25519
baseline only — scheme comparison needs a wire-format change and is out of
scope for this phase.

## What we know (with sources)

- The plugin's `Ed25519Signer` is a thin wrapper over Go stdlib
  `crypto/ed25519` (`internal/signed/packet.go`), so a standalone benchmark
  using the stdlib measures the same code path with zero plugin changes.
- The signed payload sizes: 44-byte probe payload (108-byte packet minus
  64-byte signature) and ~213-byte minimal reply payload (277 − 64). Verify
  these against `packet.go` before relying on them.
- Distributions matter more than means: `-processing-delay` calibration can
  subtract a constant but cannot remove variance (§2.1, §2.2 discussion).
- A loopback measurement on other hardware put challenged-minus-unchallenged
  at ~92 µs median, which bundles two signs, two verifies, parsing, and
  scheduling. Reconciling your isolated numbers against 001's bundle is part of
  the point — design outputs so that comparison is straightforward.
- Target hosts for the benchmark: `hap-gpu` (Threadripper 3945WX, bare metal)
  and `hap-server` (1 vCPU EPYC-Genoa KVM). Host facts: `../infra/README.md`,
  `../infra/hap-cluster.md`.

## What we assume (unverified)

- That microsecond-scale userspace benchmarking on these hosts is trustworthy
  at the precision we need. Timer resolution, `time.Now()` overhead vs cycle
  counters, frequency scaling, and Go runtime effects (GC, scheduler) all need
  either handling or honest caveats. This is the main methodological risk;
  treat it as a first-class design question, not a footnote.
- That per-operation latency (rather than throughput) is the right shape of
  number, because one signature sits in one measurement window.

## What we don't know

- Sample counts, warm-up handling, and isolation (pinning? nice levels?) that
  make the distribution stable and honest.
- Whether verification cost belongs in the window accounting the same way
  signing does — trace where verification actually happens relative to the
  anchor's timing (attester side: `internal/signed/sender_linux.go`; anchor
  side: `reflector_linux.go`) rather than assuming.
- Output format: per-op JSONL under `data/` is the working assumption (repo
  convention: raw data committed, analysis re-runnable) — design the schema.

## Constraints

- Standalone Go module under `harness/` (e.g. `harness/signbench/`), stdlib
  only, cross-compiled locally like the main binaries (`../infra/README.md`
  § Building). No Go toolchain exists on the hosts.
- Report every latency in both µs and metres at c/2.
