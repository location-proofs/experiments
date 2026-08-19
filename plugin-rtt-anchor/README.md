# plugin-rtt-anchor experiments

How far away a computer is can be bounded by how long signals take to reach it,
because nothing travels faster than light. A server at a known location (an
*anchor*) exchanges cryptographically signed packets with the machine being
located (the *attester*); the round-trip time, signed by the anchor, puts a
hard ceiling on the distance between them. This repository benchmarks that
measurement — with a focus on AI accelerators, hardware whose physical
location increasingly matters for governance and security.

We are mapping the lifecycle of a ping measurement for latency-based location
verification. The measurement is broken into granular steps — signing, the
host's own turnaround, the local network out of the facility, the wide-area
path, the anchor's handling — and each numbered experiment below establishes a
baseline for one step's contribution to the total error.

The quantity we aim to pin down is the **residual error**: the excess of the
measured minimum round-trip time over the light-travel time implied by the
true distance. Its magnitude sets how tight a location bound can be, its
variance sets how repeatable one is, and its decomposition across the steps
tells us which layer limits precision. The conversion that makes microseconds
matter: at half the speed of light (a round trip covers the distance twice),
one microsecond of unexplained delay reads as roughly 150 metres.

One step deserves particular mention: the path a ping takes *inside* the
facility — from the accelerator's host, across the local network, to the port
facing the wider internet. From outside, that segment is invisible, blended
into every wide-area number; we have not seen it characterized for this
purpose, and one experiment exists to measure our accessible instance of it.

These are calibration and benchmarking experiments. There is no headline
hypothesis to confirm; the deliverable is an error budget with every term
measured rather than assumed, and honest statements of what remains unknown.
What is unknown is tracked in the plugin's
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md)
(the §-references below point there); every question there ends with what
would settle it, and the experiments here exist to close them.

## How a measurement works, in one paragraph

One measurement is a four-packet exchange over UDP. The attester sends a
signed probe; the anchor replies with a signed packet carrying a fresh nonce;
the attester echoes the nonce in a second signed probe; the anchor replies
with a signed measurement. The anchor times the interval from its own
transmission of the first reply to its own receipt of the nonce echo — one
clock, one machine, no clock synchronization anywhere — and that interval
travels back inside the anchor's signature, so it is the only number a
verifier can rely on. The interval contains the reverse network path, the
attester's turnaround (scheduler wake-up, parsing, signing), and the forward
path. All of that noise is one-sided — queueing, scheduling, and signing only
ever add delay — which is why the estimator is the minimum over a burst of
probes: the minimum converges on true propagation time from above.

## The experiments

Four groupings, from the inside of a single measurement outward. Each
experiment directory carries a `PROMPT.md` — the design brief its method is
developed from, deliberately written as questions and constraints rather than
conclusions — and follows the repo's conventions: method fixed in `RUN.md`
before collection, raw captures committed under `data/`, conclusions only in
`REPORT.md`. **Prompted** means the brief exists but the method is not yet
designed.

### One ping — the anatomy of a single measurement

What happens inside one measurement window, step by step, and what each step
costs.

| # | Name | Question | Status |
|---|---|---|---|
| 001 | [host-jitter](001-host-jitter/) | §1.3 With the network removed (loopback), what does our own machinery cost — idle and under load? | Prompted |
| 002 | [signature-cost](002-signature-cost/) | §2.1 What does Ed25519 sign/verify cost, as a distribution, in metres? | Prompted |
| 003 | [local-segment](003-local-segment/) | What does the path from host to internet edge (NIC, driver, local network) contribute? | Prompted |
| 007 | [signing-placement](007-signing-placement/) | Where can the nonce signature happen — CPU, separate process, GPU, TEE — at what cost, with what security? | Prompted |
| 008 | [gpu-load](008-gpu-load/) | What happens to timing and challenge availability while the machine is training? | Prompted |

### Burst sampling — from pings to an estimate

A location bound comes from the minimum over a burst, not from one ping. These
establish how many probes an estimate needs and how their spacing changes what
they are worth.

| # | Name | Question | Status |
|---|---|---|---|
| 004 | [burst-convergence](004-burst-convergence/) | §1.1 How many probes before min(N) stops improving, and where is the knee? | Prompted |
| 005 | [burst-spacing](005-burst-spacing/) | §1.2 What is the effective sample size at each inter-probe spacing? | Prompted |

### Time series — measurements over time

A minimum is only meaningful while the true floor holds still.

| # | Name | Question | Status |
|---|---|---|---|
| 006 | [floor-drift](006-floor-drift/) | §1.4 Does the floor drift, on what timescale — and how quickly does evidence go stale? Standing background sampling, analyzed as a time series. | Prompted |

### Protocol — planned, unnumbered

Questions about the wire format and the wider system, mostly gated on changes
or hardware we do not yet have. Numbers are assigned at scaffold time.

| # | Name | Question | Status |
|---|---|---|---|
| — | pqc-packet-size | §2.2 Post-quantum signatures may not fit in a datagram | Planned |
| — | path-inflation | §4.2 How stable is the path-inflation ratio? | Planned |
| — | gpu-attestation | `docs/gpu-binding.md` — cost of the slow attestation loop | Planned |

Two questions deliberately hold no slot: kernel-versus-userspace receive
timestamps fold into 001/004's analysis once the plugin exports both stamps
per observation, and the trust status of the anchor itself — what evidence is
worth from a semi-trusted anchor, whether verifiable delay functions help —
is an open research question, not yet an experiment.

Numbers 001–008 were re-baselined once on 2026-08-19, before any data existed,
so the sequence builds inside-out; they are frozen from here on, and gaps are
information (an abandoned experiment keeps its number). Scaffold new
experiments with `./new-experiment.sh plugin-rtt-anchor <slug>` from the
repository root.

## Sequencing

001 runs first: it is cheap, local, and validates the entire pipeline before
any long run over the wide-area path. 002 runs in parallel and reconciles
against 001's challenged-versus-unchallenged delta. 003 waits on a local-network
reflector; 004 — the load-bearing experiment, whose knee sets the operating
point for burst size and the anchor's rate-limit design (§5.1) — follows the
instrument work and is read against it. 005 refines 004; 006 starts as a
standing background process once the path is validated. 007 waits on an
in-progress branch for GPU-side signing; 008 waits on 007.

The synthesis the phase should end with:

    one good signed ping = min-RTT at the knee (004)
                           ± host floor        (001)
                           ± signing cost      (002)
                           ± local segment     (003)

with every term in metres, and the load-dependence of each from 001 and 008.

## Scope

- **GPU *identity* is out; GPU *load* and signing *placement* are in.**
  Binding a measurement to a specific GPU needs confidential-computing
  hardware this testbed does not have (consumer Ampere; confirmed in the
  machine survey). 007 and 008 measure what can be measured honestly here.
- **Longitudinal claims are out.** What a *sequence* of measurements means as
  a claim — including completeness against cherry-picking (§3.1) — is
  downstream of knowing what one measurement is worth. 006 collects a time
  series, but to characterize the floor, not to make longitudinal claims.
- **Post-quantum signatures wait.** §2.2's packet-size analysis stands;
  measuring it requires a wire-format change.

## Testbed

Two host pairs, each with recorded ground truth — full record in
[`infra/README.md`](infra/README.md). The current phase runs on an attester in
Cambridge and an anchor in Hetzner Helsinki: 1,768 km great-circle, measured
ICMP floor 38.001 ms. The attester is node1 of a shared GPU cluster — bare
metal, quiet at rest, five power-capped RTX 3090s that double as a
controllable load generator; machine survey in
[`infra/hap-cluster.md`](infra/hap-cluster.md). The original
Falkenstein–Helsinki pair remains in use for parallel work.
