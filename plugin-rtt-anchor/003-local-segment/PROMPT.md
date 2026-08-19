# Design prompt: 003-local-segment

What does the path between the host and the port to the wider internet — NIC,
driver, local switch/router/NAT — contribute to a measurement?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. This experiment is *contingent on hardware we
have not yet inventoried*, so a large part of the deliverable is enumerating
viable designs per available reflector, not committing to one. Deliverable: a
draft `RUN.md` (per `../../TEMPLATE/RUN.md`) with clearly-marked contingencies,
for John's review. Do not run anything against any host.

## The question

001 measures the software turnaround over loopback, which never touches the
NIC. 004 measures the whole wide-area path. Between them sits an unmeasured
segment: NIC hardware and interrupt path, then the local network out to the
internet edge. The boundary John cares about is the port to the wider internet
— the edge of the attester's local network. This experiment attributes time to
that segment, closing the gap between 001's floor and 004's path numbers.

## What we know (with sources)

- `hap-gpu` sits on a 1 GbE LAN (`192.168.80.80/24`) and also has a 100 Gb/s
  InfiniBand link to a second node at `10.10.10.1/24` — but the second node
  rejects our credentials, so the IB rung is aspirational until access
  materializes (`../infra/hap-cluster.md`).
- What else is reachable on the LAN (another host? the gateway? a managed
  switch?) is unknown. John will supply an inventory; the design should state
  per option what becomes measurable.
- Loopback bypasses the NIC entirely; that is the boundary between 001 and
  this experiment (`../README.md`).
- The measurement tool of record is the anchor/attester pair itself, which
  needs a Linux KVM-or-bare-metal reflector for `SO_TIMESTAMPNS`
  (`../infra/README.md` § Host requirements). A LAN host that can run the
  anchor binary gives an apples-to-apples application-level measurement.

## What we assume (unverified)

- That an "attester → LAN reflector" RTT minus 001's loopback floor is a fair
  estimate of the NIC + LAN contribution. There is a subtlety: the reflector
  host adds its *own* turnaround, so the arithmetic needs the reflector's
  loopback baseline too. Work the algebra out explicitly in the design.
- That sending to one's own LAN IP would exercise the NIC — likely false
  (kernels typically short-circuit local addresses without touching the wire).
  Needs investigation; do not design around hairpinning without verifying it.

## What we don't know

- The reflector inventory (blocked on John). Design for the plausible cases:
  (a) a second Linux host on the LAN that can run the anchor; (b) only the
  gateway/router, reachable via ICMP — a weaker, different-stack proxy whose
  comparability to UDP application RTT needs stating honestly; (c) nothing
  suitable — in which case say what minimal hardware would unblock this.
- Whether NIC-level effects (interrupt coalescing, offloads) matter at the
  microsecond scale we care about, and whether they can be toggled or must
  simply be recorded. Needs investigation.
- Whether kernel timestamping behaves differently across loopback, LAN, and
  WAN paths in ways that confound the subtraction (ties into the demoted
  timestamp-source question; see `../README.md`).
