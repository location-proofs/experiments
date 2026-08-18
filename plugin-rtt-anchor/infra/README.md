# Testbed

Two anchors on Hetzner, roughly 1,350 km apart. The pair exists so that
measurements can be scored against a known answer — the ground-truth distance is
the point of this testbed, not the hosts themselves.

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
