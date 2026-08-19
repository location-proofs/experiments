# plugin-rtt-anchor

Experiments for [`location-proofs/plugin-rtt-anchor`](https://github.com/location-proofs/plugin-rtt-anchor),
which produces round-trip-time evidence about where a machine is.

What is unknown is recorded in that repository's
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md).
Every question there ends with what would settle it. The experiments below exist
to close them.

## Testbed

Two pairs: the original Hetzner pair (Falkenstein–Helsinki) and the
Cambridge–Helsinki pair added for the single-ping phase. See
[`infra/`](infra/) for provisioning, the coordinates we assert, and the
shared-cluster survey of the Cambridge attester host.

## Experiments

| # | Name | Settles | Status |
|---|---|---|---|
| 001 | [burst-convergence](001-burst-convergence/) | §1.1 How many probes does a burst need? | Scaffolded |
| — | burst-spacing | §1.2 Does burst spacing change what you learn? | Planned |
| — | host-jitter | §1.3 How much of the residual is our own scheduler? | Planned |
| — | floor-drift | §1.4 Does the floor drift, and on what timescale? | Planned |
| — | signature-cost | §2.1 What does each signature scheme cost in metres? | Planned |
| — | pqc-packet-size | §2.2 Post-quantum signatures may not fit in a datagram | Planned |
| — | path-inflation | §4.2 How stable is the path-inflation ratio? | Planned |
| — | gpu-load | Turnaround timing and challenge availability under GPU training load | Planned |
| — | gpu-attestation | `docs/gpu-binding.md` — cost of the slow loop | Planned |

Numbers are assigned when an experiment is scaffolded, so planned rows carry
none. Use `./new-experiment.sh plugin-rtt-anchor <slug>` from the repository
root.

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
