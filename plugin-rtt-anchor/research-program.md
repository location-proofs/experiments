# Research program: the single good signed ping

Phase document, opened 2026-08-19. Experiments live in numbered directories
beside this file; open questions live in the plugin's
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md),
and the §-references below point there.

Experiment numbers were re-baselined once, on 2026-08-19, before any data was
collected, so that the sequence reads inside-out — instrument first, then the
world. From here on numbers are frozen, per the repository's conventions.

## What this phase establishes

The plugin can produce a signed RTT observation. What we do not yet know is what
one observation is worth — how accurate it is, what it costs to collect, and
which conditions degrade it. This phase treats the single signed measurement as
the unit under test, before any question about sequences of measurements,
geofences, or longitudinal claims (those are parked in §6).

The unit conversion that makes this urgent: at c/2, one microsecond of delay
inside the measured window reads as roughly 150 metres of apparent distance.
Scheduling jitter, signing time, and timestamping error are all inside that
window. A distance bound is only as tight as our account of where the
microseconds go — so the deliverable of the phase is an error budget, with every
term measured rather than assumed.

## How a measurement works, in one paragraph

One measurement is a four-packet exchange over UDP. The attester sends a signed
probe; the anchor replies with a signed packet carrying a fresh nonce; the
attester echoes the nonce in a second signed probe; the anchor replies with a
signed measurement. The anchor times the interval from its own transmission of
the first reply to its own receipt of the nonce echo — one clock, one machine,
no clock synchronization anywhere — and that interval travels back inside the
anchor's signature, so it is the only number a verifier can rely on. The
interval contains the reverse network path, the attester's turnaround
(scheduler wake-up, parsing, signing), and the forward path. All of the noise in
those segments is one-sided — queueing, scheduling, and signing only ever add
delay — which is why the estimator is the minimum over a burst of probes: the
minimum converges on true propagation time from above.

## The questions, as experiments

Each experiment isolates one term of the budget, so the sources disambiguate
rather than blur together. The order builds inside-out: characterize the
instrument before pointing it at the world. Numbered directories follow the
repo's conventions: method fixed in `RUN.md` before collection, raw captures
committed under `data/`, conclusions only in `REPORT.md`. Each directory also
carries a `PROMPT.md` — the design brief the experiment's method is developed
from, deliberately written as questions and constraints rather than
conclusions, because every one of these deserves more interrogation than a
first draft can give it.

**001 · host-jitter (§1.3) — the machine.** When propagation is approximately
zero — anchor and attester on the same host, talking over loopback — whatever
RTT the pipeline reports is our own machinery: scheduler wake-up, parsing,
signing, kernel crossings. Run idle, under CPU load, and under stepped GPU
training load (the first increment of the gpu-load question), challenged and
unchallenged. Deliverable: the host floor and tail per condition — the
irreducible term every other number sits on. One boundary to keep in view:
loopback packets never touch the NIC, so NIC and driver costs are not measured
here; they belong to 003.

**002 · signature-cost (§2.1, Ed25519 baseline) — the crypto.** What does
signing cost in metres? A standalone microbenchmark of Ed25519 sign and verify
at exactly the payload sizes the protocol uses, reported as distributions
rather than means, because a constant offset can be calibrated away and spread
cannot. Deliverable: the signing term of the budget, and a cross-check —
sign-plus-verify should account for most of 001's challenged-versus-
unchallenged delta, and the residual is parsing and scheduling.

**003 · local-segment — to the edge.** Between the host and the port to the
wider internet sits a segment loopback never sees: NIC hardware and driver
interrupts, then the local network — switch, router, NAT. It is currently
blended invisibly into every wide-area number. Measuring it needs a reflector
inside that boundary, and what hardware is available for that is still an open
question. Deliverable: the local segment's contribution, closing the gap
between 001's floor and 004's path measurements.

**004 · burst-convergence (§1.1) — the path.** How many probes does a burst
need before the minimum stops improving? This is the load-bearing experiment of
the phase. The convergence rate of min(N) is what converts probes, seconds, and
CPU into bound tightness, and its knee is the operating point for everything
downstream — including the anchor's rate-limit design (§5.1). Method sketch:
one large capture over the real path, subsampled into every burst size, repeated
at several times of day. Its results are read against 001 and 003, which is why
it comes after them.

**005 · burst-spacing (§1.2) — the burst's shape.** Fifty probes 20 ms apart
and fifty probes 2 s apart cost the same but sample the network differently: a
tight burst shares routing state and queue occupancy, so its samples are
correlated and the effective sample size is smaller than N. Deliverable:
effective sample size per spacing — which decides whether "answer in one
second" and "answer well" are compatible, and feeds back into how 004's curve
(measured at one fixed spacing) is read.

**006 · floor-drift (§1.4) — the floor over time.** The minimum over a window
is only meaningful if the true floor is stable across the window; a millisecond
of route drift reads as 150 km of apparent movement from a machine that never
moved. The intended shape is a standing process, not a one-off run: ongoing
slow background sampling, analyzed as a time series of per-window minima, with
random subsampling to simulate a verifier arriving at an arbitrary moment.
Deliverable: how quickly evidence goes stale, and the maximum useful
measurement window.

**007 · signing-placement — where the key lives.** The nonce signature
currently happens in userspace, on the CPU, with a software-held key. It could
instead happen in a separate process, in a GPU kernel with the key in VRAM, or
— on future hardware — inside a TEE. Each placement has a measurable in-window
timing cost and a distinct security story; on this testbed's consumer GPUs a
GPU placement protects nothing, but it prices the placement, which is what
decides whether the secured version on capable hardware could survive the
timing window. A collaborator's in-progress branch for GPU-side signing should
ground this design before anything is assumed about it.

**008 · gpu-load — under real work.** The class of machine this method most
wants to locate is a GPU host that is actually working — and that is the state
hardest to measure in. Training loads the CPU cores the turnaround runs on
(data loading, kernel launches), contends for memory and PCIe bandwidth, and —
once signing involves the GPU at all — raises the question of what happens when
the signer is busy. Two measurable questions: how the turnaround's floor and
tail move as the machine steps from idle to saturated, and what fraction of
challenges complete within timeout during sustained training. The first
increment lands as a condition in 001; the full treatment depends on 007's
placement findings, which is why it runs last.

The security question 008 opens is not soundness — noise is one-sided, so a
loaded host can only ever look *farther away* than it is, and the max-distance
bound survives. The risks are subtler. If challenges degrade or fail under
load, honest evidence clusters in idle windows, and a verifier faces a choice
between sparse, prover-timed evidence — exactly the cherry-picking surface
§3.1 names — and rejecting honest busy machines outright. Load also becomes a
deniable way to dodge measurement: "we were training" and "we chose not to
answer" produce the same evidence stream. Quantifying the timing side is what
makes these risks arguable in either direction.

Two questions deliberately hold no slot. Kernel-versus-userspace receive
timestamps (what the two ways of reading arrival time disagree by) folds into
001's and 004's analysis once the plugin exports both stamps per observation.
And the trust status of the anchor itself — what evidence is worth when the
anchor is only semi-trusted, whether verifiable delay functions help (first
read: probably not, they prove time passed rather than that it did not) — is
recorded as an open question needing research, not yet an experiment.

## Sequencing

001 runs first because it is cheap, local, and validates the entire pipeline —
binaries, kernel timestamping, capture format, analysis tooling — before any
long run over the wide-area path. 002 runs in parallel (it takes minutes) and
reconciles against 001. 003 runs when a reflector inside the local boundary is
identified. 004 follows the instrument work, and its report carries the
synthesis. 005 refines 004's parameters; 006 starts as a standing background
process once the path is validated. 007 waits on the collaborator's GPU-signing
branch; 008 waits on 007.

The synthesis the phase should end with:

    one good signed ping = min-RTT at the knee (004)
                           ± host floor        (001)
                           ± signing cost      (002)
                           ± local segment     (003)

with every term in metres, and the load-dependence of each term from 001's
conditions and 008.

## Explicitly out of scope

- **GPU binding.** Attaching the measurement to a specific GPU (via confidential
  computing attestation and an ephemeral in-enclave key) is the open problem the
  plugin's `docs/gpu-binding.md` describes. Nothing in this phase touches it —
  and the current attester host cannot: consumer Ampere has no
  confidential-computing support, confirmed in the machine survey. GPU *load*
  and signing *placement* are in scope (007, 008); GPU *identity* is not.
- **Time series and geofence semantics.** Everything in §6 — what a sequence of
  measurements means as a claim, completeness against cherry-picking (§3.1) —
  is downstream of knowing what one measurement is worth. (006 collects a time
  series, but to characterize the floor, not to make longitudinal claims.)
- **Post-quantum signatures.** §2.2's packet-size analysis stands; measuring it
  requires a wire-format change and waits for a later phase.

## Testbed

Two host pairs, each with recorded ground truth — full details in
[`infra/README.md`](infra/README.md). This phase runs on
the newer pair: an attester in Cambridge and an anchor in Hetzner Helsinki,
1,768 km apart, with a measured ICMP floor of 38.001 ms. The attester is node1
of a shared GPU cluster — bare metal, quiet at rest, with five power-capped
RTX 3090s that make it a controllable load generator for the gpu-load work;
the full machine survey is in
[`infra/hap-cluster.md`](infra/hap-cluster.md). The
original Falkenstein–Helsinki pair remains in use for parallel work and is
untouched by these experiments.
