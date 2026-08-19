# plugin-rtt-anchor

Experiments for [`location-proofs/plugin-rtt-anchor`](https://github.com/location-proofs/plugin-rtt-anchor),
which produces round-trip-time evidence about where a machine is.

What is unknown is recorded in that repository's
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md).
Every question there ends with what would settle it. The experiments below exist
to close them. The current phase — what a single good signed ping is worth —
is framed in [`research-program.md`](research-program.md).

## Testbed

Two pairs: the original Hetzner pair (Falkenstein–Helsinki) and the
Cambridge–Helsinki pair added for the single-ping phase. See
[`infra/`](infra/) for provisioning, the coordinates we assert, and the
shared-cluster survey of the Cambridge attester host.

## Experiments

| # | Name | Settles | Status |
|---|---|---|---|
| 001 | [host-jitter](001-host-jitter/) | §1.3 How much of the residual is our own scheduler? | Prompted |
| 002 | [signature-cost](002-signature-cost/) | §2.1 What does Ed25519 cost in metres? (baseline) | Prompted |
| 003 | [local-segment](003-local-segment/) | What does host-to-internet-edge contribute? | Prompted |
| 004 | [burst-convergence](004-burst-convergence/) | §1.1 How many probes does a burst need? | Prompted |
| 005 | [burst-spacing](005-burst-spacing/) | §1.2 Does burst spacing change what you learn? | Prompted |
| 006 | [floor-drift](006-floor-drift/) | §1.4 Does the floor drift, and on what timescale? | Prompted |
| 007 | [signing-placement](007-signing-placement/) | Where can the nonce signature happen, at what cost, with what security? | Prompted |
| 008 | [gpu-load](008-gpu-load/) | Timing and challenge availability under GPU training load | Prompted |
| — | pqc-packet-size | §2.2 Post-quantum signatures may not fit in a datagram | Planned |
| — | path-inflation | §4.2 How stable is the path-inflation ratio? | Planned |
| — | gpu-attestation | `docs/gpu-binding.md` — cost of the slow loop | Planned |

Numbers are assigned when an experiment is scaffolded, so planned rows carry
none. Use `./new-experiment.sh plugin-rtt-anchor <slug>` from the repository
root. Numbers 001–008 were re-baselined once on 2026-08-19, before any data
existed, so the sequence builds inside-out (instrument → crypto → local network
→ path → time → placement → load); they are frozen from here on. **Prompted**
means the directory is scaffolded and carries a `PROMPT.md` — the design brief
its `RUN.md` will be developed from — but the method is not yet designed.

## Notes on sequencing

**§1.1 is load-bearing.** The convergence curve it produces sets the operating
point for burst size, and §5.1's token-bucket parameters fall out of it
arithmetically. Most other experiments are cheaper to interpret once it is done.

**The signature experiments need a wire-format change first.** `signatureSize` is
hardcoded to 64 and `Signature` is a `[64]byte` in the packet struct, so swapping
scheme is not a configuration change. Landing a pluggable signer with an
algorithm identifier in the plugin turns §2.1 and §2.2 into a config sweep rather
than a set of branches.

**The GPU work needs cluster access** and is gated on confidential computing
being enabled on the host. See `docs/gpu-binding.md` in the plugin repository for
why the GPU cannot sit inside the timing loop, and what the two-loop construction
asks for instead.
