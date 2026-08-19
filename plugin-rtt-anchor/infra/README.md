# Testbed

Two host pairs, each with a known ground-truth distance so that measurements can
be scored against a known answer — the ground-truth distance is the point of this
testbed, not the hosts themselves.

The original Hetzner pair (`xo-server` / `geobeat-ingest`) is documented first
and is in active use by a collaborator. The second pair (`hap-gpu` /
`hap-server`) was added 2026-08-19 for the single-good-ping benchmarking phase;
new experiments run on it unless stated otherwise.

## Hosts

| | `xo-server` | `geobeat-ingest` |
|---|---|---|
| Site | `fsn1-dc8`, Falkenstein | `hel1-dc2`, near Helsinki |
| Coordinates asserted | 50.4779, 12.3713 | 60.2934, 25.0378 |
| Virtualization | KVM | KVM |
| Architecture | x86_64 | x86_64 |
| Distribution | Ubuntu 24.04 | Ubuntu 24.04 |

Both hosts run unrelated production workloads. Neither is a quiet box, and that
is deliberate — it is the realistic case, and §1.3 exists to quantify what it
costs.

## Ground truth

| | |
|---|---|
| Great-circle distance | 1,348 km |
| Measured minimum RTT | 25.140 ms |
| Provable bound at vacuum c | 3,768 km |
| Ratio of bound to true distance | 2.79x |
| Implied path velocity | 0.36c |

Measured 2026-08-18 with 20 ICMP probes. The gap between 1,348 km and the
3,768 km bound is routing indirection, not medium — see §4.2.

## The coordinates are self-asserted

Hetzner does not publish datacenter coordinates. The figures above are accurate
to roughly ±10 km, which is immaterial against a bound of several thousand
kilometres but should not be quietly forgotten.

This is precisely the weakness the plugin's README names: a measurement is only
as good as your trust in whoever runs the anchor, and there is no endorsed anchor
directory. For a testbed this is fine. It would not be fine for a claim anyone
relies on.

## Baseline jitter

Scheduling overshoot, measured over 500 one-millisecond sleeps. Jitter lands
inside the measurement, so this is the noise floor the estimator has to work
against.

Both hosts were sampled twice on 2026-08-18, several hours apart, under very
different load. `xo-server` was remediated between the two runs — its root
filesystem had been full, with `apport` crash-looping at 79% CPU.

| Host | 1-min load | min | p50 | p90 | p99 | max |
|---|---|---|---|---|---|---|
| `xo-server` | 4.74 | 25 us | 78 us | 98 us | 927 us | 1952 us |
| `xo-server` | 0.45 | 25 us | 99 us | 141 us | 899 us | 1818 us |
| `geobeat-ingest` | 4.09 | 20 us | 79 us | 140 us | 1188 us | 2626 us |
| `geobeat-ingest` | 8.87 | 32 us | 91 us | 116 us | 201 us | 944 us |

At `c/2`, one microsecond is about 150 metres. So the floor costs roughly 3 to
5 km and a p99 excursion anywhere from 30 to 180 km.

**Load did not predict jitter in either direction.** `xo-server` shed a factor of
ten in load and its median got slightly worse; `geobeat-ingest` doubled its load
and its p99 improved six-fold. The tail moved unpredictably across a twenty-fold
swing in load between hosts.

The floor did not. It stayed between 20 and 32 microseconds across every run —
which is the number the minimum estimator actually consumes, and is a preliminary
point in favour of co-tenancy being tolerable.

Treat that as a hint rather than a result. It is four uncontrolled samples of 500
sleeps, and sleep overshoot is a proxy for the scheduling behaviour that matters
rather than a measurement of it. Settling it is what §1.3 is for.

Hypervisor steal time was 0.0% on both hosts in both runs, so oversubscription at
the Hetzner layer is not a factor.

## Second pair: `hap-gpu` → `hap-server`

| | `hap-gpu` | `hap-server` |
|---|---|---|
| Hostname | `testbed-node1` | `ubuntu-2gb-hel1-1` |
| Site | Cambridge, UK | Hetzner `hel1`, near Helsinki |
| Coordinates asserted | 52.20653, 0.12018 | 60.34329, 25.02972 |
| Virtualization | bare metal | KVM |
| CPU | Threadripper PRO 3945WX, 12c/24t | 1 vCPU, EPYC-Genoa |
| Public IPv4 | none needed — NAT, outbound only | 37.27.183.180 |
| Distribution | Ubuntu 26.04 | Ubuntu 26.04 |
| Role | attester | anchor |

`hap-gpu` is a bare-metal workstation and was essentially idle when surveyed
(1-min load 0.08), so unlike the pair above it can serve as a quiet-host
baseline. It also carries the GPU for the eventual binding work, though that is
out of scope for this phase — here it is only the attester host.

`hap-server` has a single vCPU. That is enough for anchor duty — signing and
verifying at burst rates is tens of microseconds per pair — but it matters for
loopback runs (§1.3): anchor and attester would compete for the same core while
the sender busy-polls up to 15 ms per pair, so loopback figures from this host
read as a contention-inflated worst case rather than a floor. The loopback
baseline belongs on `hap-gpu`; the `hap-server` loopback run is kept for exactly
that contrast.

### Ground truth

| | |
|---|---|
| Great-circle distance | 1,768 km |
| Measured minimum RTT | 38.001 ms |
| Provable bound at vacuum c | 5,696 km |
| Ratio of bound to true distance | 3.22x |
| Implied path velocity | 0.31c |

Measured 2026-08-19 with 20 ICMP probes at 200 ms spacing, from `hap-gpu` to
`37.27.183.180`. The spread was unusually tight — max − min under 1 ms, mdev
0.188 ms — which suggests a stable, uncongested route and bodes well for the
minimum estimator.

The `hap-gpu` coordinates are self-asserted by its operator, who is standing
next to it — the strongest assertion available, and still an assertion. The
`hel1` coordinates here are a refinement of the dc-level guess used for
`geobeat-ingest` above; the ±10 km caveat in the section below applies to the
Hetzner end regardless.

## Host requirements

The reflector sets `SO_TIMESTAMPNS` and exits if it cannot, so a shared-kernel
VPS (OpenVZ, LXC) may refuse to run it. **KVM or bare metal only.** Both hosts
above qualify.

An anchor also needs a public static IPv4 address and one inbound UDP port. The
socket is `AF_INET`, so IPv4 only. No elevated capabilities are required — it is
an ordinary unprivileged UDP socket.

The attester needs **outbound UDP only**. It initiates every exchange, so it
works from behind NAT and needs no inbound rules. This matters for the cluster
work, where inbound access is usually unavailable.

## Building

Binaries are statically linked, so cross-compile locally and copy them across.
No Go toolchain is needed on the hosts.

```sh
GOOS=linux GOARCH=amd64 go build -o anchor   ./cmd/anchor
GOOS=linux GOARCH=amd64 go build -o attester ./cmd/attester
```

Record the commit you built from in the experiment's `RUN.md`. A binary with no
recorded provenance cannot be reproduced.

## Firewall

Each anchor needs its listening port opened. Neither host allows it by default.

```sh
sudo ufw allow 8924/udp
```

## Running an anchor

From the plugin's `docs/deployment.md`. Coordinates must be the real ones — the
binary refuses the null-island coordinate, but it cannot detect a plausible lie.

```ini
[Unit]
Description=RTT location anchor
After=network-online.target

[Service]
ExecStart=/usr/local/bin/anchor \
  -id anchor-fsn-1 \
  -lat 50.4779 -lng 12.3713 \
  -listen 0.0.0.0:8924 \
  -key /etc/rtt-anchor/key.json \
  -allowlist /etc/rtt-anchor/allowlist.txt
User=rtt-anchor
Restart=always
RestartSec=5

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/etc/rtt-anchor

[Install]
WantedBy=multi-user.target
```

The key file must be mode 0600 and owned by the service user. The binary refuses
to overwrite an existing key, so a restart cannot silently rotate identity and
invalidate every allowlist naming it.

## Enrolling an attester

1. On the attester: `attester -print-key`.
2. Append that key to the anchor's `allowlist.txt` with a label.
3. The anchor re-reads the allowlist every 30 seconds. No restart.

Removal is the same in reverse. There is no revocation beyond the allowlist.

## Collecting

Observations go to stdout as one JSON object per line; logs go to stderr. So the
evidence stream needs no wrapper:

```sh
attester -anchor <host>:8924 -anchor-key <key> -json -raw >> data/capture.jsonl
```

`-raw` includes the anchor-signed reply bytes. Those are the part that
constitutes evidence — everything else in the record is a reading of them.
Collect without `-raw` and you have discarded the proof.
