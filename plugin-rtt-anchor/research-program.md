# Research program: the single good signed ping

Phase document, opened 2026-08-19. Experiments live in numbered directories
beside this file; open questions live in the plugin's
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md),
and the §-references below point there.

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
rather than blur together. Numbered directories follow the repo's conventions:
method fixed in `RUN.md` before collection, raw captures committed under
`data/`, conclusions only in `REPORT.md`.

**002 · host-jitter (§1.3).** When propagation is approximately zero, what RTT
does the pipeline report — and how does it move with load? Anchor and attester
run on the same host, so the reported RTT *is* the combined processing and
scheduling cost. Run idle and under synthetic load, challenged and unchallenged.
Deliverable: the host floor and tail per condition — the irreducible term that
every other number sits on. This also settles whether a busy co-tenant host
costs accuracy, which decides whether process pinning or a quieter host is
worth anything.

**004 · signature-cost (§2.1, Ed25519 baseline).** What does signing cost in
metres? A standalone microbenchmark of Ed25519 sign and verify at exactly the
payload sizes the protocol uses, reported as distributions rather than means,
because a constant offset can be calibrated away and spread cannot. Deliverable:
the signing term of the budget, and a cross-check — sign-plus-verify should
account for most of 002's challenged-versus-unchallenged delta, and the residual
is parsing and scheduling.

**001 · burst-convergence (§1.1).** How many probes does a burst need before the
minimum stops improving? This is the load-bearing experiment of the phase. The
convergence rate of min(N) is what converts probes, seconds, and CPU into bound
tightness, and its knee is the operating point for everything downstream —
including the anchor's rate-limit design (§5.1), which falls out of it
arithmetically. Method: one 10,000-pair burst at fixed 20 ms spacing over the
real path, repeated at three times of day, bootstrap-subsampled at N = 1 through
500. Deliverable: the convergence curve and its knee, priced in metres per
probe.

**003 · timestamp-source (new §1.5).** The sender captures three timestamps per
reply — a userspace send time, a kernel receive stamp, and a userspace fallback
— then collapses them into one number before reporting. What do the kernel and
userspace stamps disagree by, and which clock should be believed? Blocked on a
small additive change to the plugin (export both stamps per observation; no wire
format change). Deliverable: the timestamping term of the budget, and a
go/no-go on trusting the attester host's kernel stamps before the large runs.

**005 · burst-spacing (§1.2).** Fifty probes 20 ms apart and fifty probes 2 s
apart cost the same but sample the network differently: a tight burst shares
routing state and queue occupancy, so its samples are correlated and the
effective sample size is smaller than N. Fix N = 50 and sweep spacing from 1 ms
to 1 s. Deliverable: effective sample size per spacing — which decides whether
"answer in one second" and "answer well" are compatible.

**006 · floor-drift (§1.4).** The minimum over a window is only meaningful if
the true floor is stable across the window; a millisecond of route drift reads
as 150 km of apparent movement. Twenty pairs every fifteen minutes for a week,
unattended. Deliverable: the maximum useful measurement window.

## Sequencing

002 runs first because it is cheap, local, and validates the entire pipeline —
binaries, kernel timestamping, capture format, analysis tooling — before any
long run over the wide-area path. 004 runs in parallel (it takes minutes) and
reconciles against 002. 001 runs once the pipeline is proven, and its report
carries the synthesis. 003 waits on the plugin change. 005 and 006 follow 001,
which sets the context they are interpreted in.

The synthesis the phase should end with:

    one good signed ping = min-RTT at the knee (001)
                           ± host floor        (002)
                           ± timestamp error   (003)
                           ± signing cost      (004)

with every term in metres.

## Explicitly out of scope

- **GPU binding.** Attaching the measurement to a specific GPU (via confidential
  computing attestation and an ephemeral in-enclave key) is the open problem the
  plugin's `docs/gpu-binding.md` describes. Nothing in this phase touches it;
  the attester host happens to carry a GPU, but here it is only a quiet
  bare-metal box.
- **Time series and geofence semantics.** Everything in §6 — what a sequence of
  measurements means, completeness against cherry-picking (§3.1) — is
  downstream of knowing what one measurement is worth.
- **Post-quantum signatures.** §2.2's packet-size analysis stands; measuring it
  requires a wire-format change and waits for a later phase.

## Testbed

Two host pairs, each with recorded ground truth — full details in
[`infra/README.md`](infra/README.md). This phase runs on the newer pair: an
attester in Cambridge (bare metal, quiet) and an anchor in Hetzner Helsinki,
1,768 km apart, with a measured ICMP floor of 38.001 ms. The original
Falkenstein–Helsinki pair remains in use for parallel work and is untouched by
these experiments.
