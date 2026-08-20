# Run: 001-host-jitter

The reproducibility contract. **Draft for review — the method is not frozen and
nothing has been collected.** Line numbers cite the pinned commit below.

## Question

With the network removed — anchor and attester on one machine, over loopback —
what does our own measurement machinery cost, idle and under load?

**Open question:** [§1.3 in the plugin's docs/open-questions.md](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md#13-how-much-of-the-residual-is-our-own-scheduler)

This is a zero-baseline run: true distance is zero, propagation is
approximately zero, so the interval the anchor reports is the instrument's
self-noise — its floor, its tail, and its sensitivity to load. Two scoping
limits apply to everything below:

- **The reported interval sums two processes' costs.** Between the anchor's two
  stopwatch stamps sit the anchor's own send path, the attester's entire
  turnaround, and the loopback deliveries. A single number cannot attribute
  cost to a side. The pinned attester binary does not export what the
  decomposition needs (see "What the JSONL exports today"), so until the
  proposed export change lands, every number from this run is a **combined**
  cost. CPU pinning (same core versus separate cores) is the coarse
  decomposition axis available today and is in the condition matrix.
- **Loopback packets never touch the network card.** The kernel turns them
  around internally, so this run says nothing about NIC, driver, or interrupt
  costs; those belong to 003-local-segment. Do not read these numbers as a
  host-plus-local-network floor.

## Background: the measured window, traced through the code

Neither the reader nor the analysis should have to reason about an untraced
path. This section follows one challenged probe pair through both binaries at
the pinned commit. Both processes' hot paths run on locked OS threads
(`runtime.LockOSThread`: `sender_linux.go:320`, `reflector_linux.go:157`).

### Attester side

The attester runs challenged by default (`cmd/attester/main.go:111` passes
`!*unchallenged` into `signed.NewSender`, which returns a `LinuxSender`;
`sender.go:29-31`). One pair, in `probePairChallenged`
(`sender_linux.go:319-365`):

1. **Build and sign probe 0.** `NewProbePacket` (`packet.go:111-132`) stamps
   `Sec`/`Frac` with the current NTP time and Ed25519-signs the 44-byte
   payload. This happens before any I/O.
2. **Send probe 0 and wait for reply 0** via `sendAndRecv`
   (`sender_linux.go:369-423`): `sendTime = time.Now()` immediately before
   `unix.Sendto` (lines 370-371), then a busy-poll phase — `EpollWait` with
   timeout 0 in a tight loop for up to 15 ms from send (`busyPollWindow`,
   line 22; loop 383-396) — then a blocking `EpollWait` phase until the pair
   deadline. The busy-poll is why the attester's wake-up cost is far below a
   sleeping process's, and why it occupies a core while waiting.
3. **Receive and parse reply 0** in `tryRecv` (`sender_linux.go:427-489`):
   `Recvmsg` with ancillary data, a userspace fallback stamp, size check,
   `UnmarshalReplyPacket`, seq/Sec/Frac match against probe 0. Signature
   verification is deliberately skipped for reply 0 (`verify=false`, call at
   line 339; rationale in the comment at 333-338) — a spoofed reply 0 just
   yields a nonce the anchor will not recognize. The kernel receive stamp is
   pulled from the `SO_TIMESTAMPNS` control message (473-487) and
   `decideRTT` (498-504) computes the attester's own RTT0 from it, falling
   back to the userspace stamp if the kernel stamp reads more than 100 µs
   *before* the send time, and clamping at zero.
4. **Extract the nonce.** The anchor smuggles it in reply 0's
   `SinceLastRxNs` field (`sender_linux.go:345`; field layout
   `packet.go:87,99`).
5. **Build and sign probe 1.** `newChallengedProbePacket`
   (`packet.go:138-156`) writes the nonce into `Sec` (upper 32 bits) and
   `Frac` (lower 32), then Ed25519-signs the 44-byte payload. This signing is
   inside the anchor's measured window — it is the cost the challenge
   deliberately forces into the measurement.
6. **Send probe 1** via a second `sendAndRecv` (line 354): `time.Now()`, then
   `unix.Sendto`. This packet is what stops the anchor's stopwatch. The
   attester then waits for reply 1 (verified this time) and reports.

### Anchor side, and exactly where the two stopwatch stamps are taken

The anchor lives in `LinuxReflector` (`reflector_linux.go`; `cmd/anchor`
reaches it through `signed.NewReflector`, `reflector.go:22-24`). One
single-goroutine epoll loop (`Run`, `reflector_linux.go:156-328`) handles
everything. Per probe:

1. `Recvmsg` with ancillary data (line 193), size check (201),
   `UnmarshalProbePacket` (205), allowlist check on the sender pubkey (214).
   Note the anchor never verifies the probe's Ed25519 signature —
   authentication is allowlist membership; per-probe signature verification is
   left to downstream verifiers (comment at 247-249).
2. `now := kernelTimestamp(oob[:oobn])` (line 221): the kernel's
   `SO_TIMESTAMPNS` receive stamp for this packet, taken by the kernel at
   delivery to the socket, not by userspace after scheduling. The socket
   option is mandatory — the constructor fails without it (92-96) — but
   `kernelTimestamp` (353-369) silently falls back to `time.Now()` if a
   particular packet's control message is missing or unparseable.
3. **Probe 0 branch** (267-277): generate an 8-byte nonce from `crypto/rand`
   (`randomNonce`, 345-351), place it in the reply's `SinceLastRxNs` slot.
4. **Reply construction and signing** (`NewReplyPacket`, called at line 314;
   `packet.go:292-327`): marshal the ~451-byte payload and Ed25519-sign it.
   This happens **before** the stopwatch starts.
5. **Stopwatch start:** `state.lastTxTime = time.Now()`
   (`reflector_linux.go:321`) — a **userspace clock read taken immediately
   before `unix.Sendto`** of reply 0 (line 322). The reply's construction and
   signing are outside the window; the `Sendto` syscall and everything after
   it are inside.
6. **Stopwatch stop:** when probe 1 arrives, the same `now :=
   kernelTimestamp(...)` at line 221 is its stop stamp — the **kernel receive
   timestamp applied at packet delivery**. The anchor process may be
   descheduled for arbitrarily long before it actually reads the packet; that
   delay does not enter the interval.
7. **Probe 1 branch** (278-290): reconstruct the presented nonce from
   `probe.Sec`/`Frac`, set the challenged flag on match (281-283), and compute
   the signed interval: `sinceLastRxNs = uint64(now.Sub(state.lastTxTime).
   Nanoseconds())` (287-289). That value travels in anchor-signed reply 1 and
   surfaces as `anchor_measured_rtt_ns`.

### What sits inside the window

For a challenged pair on loopback, in order:

| # | Component | Side |
|---|---|---|
| 1 | `Sendto` syscall for reply 0, kernel loopback queueing and delivery | anchor + kernel |
| 2 | Attester wake (busy-poll exit or epoll wake), `Recvmsg` | attester |
| 3 | Reply 0 unmarshal, field checks, control-message parse | attester |
| 4 | Nonce extraction, probe 1 build, **Ed25519 sign**, marshal | attester |
| 5 | `time.Now()` and `Sendto` for probe 1 | attester |
| 6 | Kernel loopback delivery of probe 1, `SO_TIMESTAMPNS` stamp at delivery | kernel |

Outside the window: the anchor's reply-0 construction and signing (before the
start stamp), the anchor's own scheduling delay in picking up probe 1 (after
the stop stamp), and everything to do with reply 1.

### Clock domains — the two stamps are not on the same clock path

The start stamp is a Go `time.Now()`, which carries both wall and monotonic
readings. The stop stamp is reconstructed from the kernel's timespec with
`time.Unix(...)` (`reflector_linux.go:363`), which carries **no** monotonic
reading. Go's documented `time.Time.Sub` semantics use the monotonic clock
only when both operands have it; otherwise the subtraction is wall-clock. So
the anchor's signed interval is a **CLOCK_REALTIME difference**, exposed to
clock discipline between the two stamps:

- NTP *slew* is bounded (ordinarily ≤ 500 ppm), so over a ~200 µs window it
  contributes at most ~0.1 µs, either direction. Second-order, but it is a
  genuinely two-sided term in an otherwise one-sided error budget.
- A clock *step* between the stamps is unbounded. A backward step makes
  `now.Sub(lastTxTime)` negative, and the `uint64` conversion at line 288
  wraps it to an astronomically large value. The analysis plan screens for
  this signature.
- The attester's `decideRTT` guard — fall back to the userspace stamp when
  the kernel stamp reads more than 100 µs before send
  (`sender_linux.go:498-504`) — is in-code evidence that negative wall-clock
  deltas of that size have been observed on the attester side. The anchor's
  interval computation has no equivalent guard. Why deltas that large occur
  is **needs investigation** (git history of that guard, plus a run exporting
  both stamps per observation, would answer it).

### The unchallenged contrast

In unchallenged mode (`probePairUnchallenged`, `sender_linux.go:140-311`) both
probes are built and signed before any I/O (147-160). When a packet matching
reply 0 arrives, probe 1 is fired after only a 4-byte sequence check — before
any parsing, which is deferred until after the send (185-210, 255-279). The
challenged-minus-unchallenged delta therefore isolates, inside the window:
reply-0 unmarshal and checks, control-message parse, nonce extraction, probe-1
build, Ed25519 sign, and marshal — less the unchallenged path's seq check and
ancillary-buffer copy. This is the quantity to reconcile with
002-signature-cost's isolated signing numbers.

### What the JSONL exports today

Per pair (`cmd/attester/main.go`, `observation`, lines 169-212):

- `anchor_measured_rtt_ns` — reply 1's `SinceLastRxNs`, the signed interval
  (line 232). The primary variable of this experiment.
- `attester_measured_rtt_ns` — `min(RTT0, RTT1)` (line 234), where RTT0 is
  send-probe-0 → kernel-arrival-of-reply-0 and RTT1 is send-probe-1 →
  kernel-arrival-of-reply-1, both attester-side. **The minimum only**;
  the two are not exported separately, although `ProbePairResult` already
  carries both (`sender.go:11-16`).
- `timestamp` — RFC 3339 at **one-second resolution** (`now()`, line 355). At
  100 ms pair spacing, ten observations share a stamp; ordering comes from
  `seq` only, and sub-second drift analysis is impossible from this field.
- `challenged`, signature-validity flags, coordinates, distance conversions,
  and (with `-raw`) the anchor-signed reply bytes — the actual evidence.

**Not exported anywhere:** the attester's turnaround (kernel arrival of reply
0 → `Sendto` of probe 1). Both endpoints exist as locals in
`probePairChallenged` (the kernel stamp inside `tryRecv`, the send time inside
the second `sendAndRecv`) but are not surfaced. Without it the anchor's
interval cannot be split into attester-side and anchor-plus-kernel-side costs.

## Points of disagreement with the brief

1. **"Starts its stopwatch as that reply leaves" is not quite what the code
   does.** The start stamp is a userspace `time.Now()` taken before the
   `Sendto` syscall (`reflector_linux.go:321-322`), so the anchor's entire
   send path — syscall entry, kernel queueing, loopback delivery — is inside
   the window, and any delay between the stamp and actual packet movement
   *adds* to the interval. The distinction matters for decomposition: the
   "anchor-side" residue is not zero even in principle.
2. **The brief's proposed two-sided mechanism is not supported by the code as
   written.** It suggests jitter in where the send stamp is taken "relative to
   when the packet actually moves could shift the measured interval in either
   direction." Because the stamp is strictly before departure, that mechanism
   is one-sided — it only lengthens the interval. The skepticism about
   minimum-over-burst survives, but on a corrected mechanism: the interval is
   a wall-clock difference across two differently-sourced stamps, so clock
   slew (small, bounded) and clock steps (rare, unbounded, wrapping to absurd
   values) are the genuinely two-sided terms. See "Clock domains" above.
3. **The full load-type axis overlaps 008-gpu-load.** The brief asks for
   idle / synthetic CPU / real training load steppable across 1-5 GPUs. Real
   training load is exactly 008's question, and standing up a training
   workload is its own instrument-building task. Proposed split: 001 runs
   idle and synthetic CPU load, and states plainly that synthetic CPU load
   exercises run-queue pressure only — not dataloader threads, PCIe
   interrupt traffic, or memory bandwidth; 008 runs the GPU-stepped axis
   against 001's baseline. An optional single-GPU pilot cell is listed below
   for John to accept or strike. How far any load result generalizes across
   hardware and operating systems remains an open question either way.
4. **Minor:** the brief says the attester "busy-polls for up to 15 ms while
   waiting for each reply." Correct for the challenged path and for reply 0
   of the unchallenged path; the unchallenged path's wait for reply 1 has no
   busy-poll phase (`probePairUnchallenged` waits with blocking `EpollWait`
   only, lines 281-310). Immaterial to the measured window; recorded for
   trace completeness.

## Proposed plugin changes (branch; proposed, not yet written)

Recorded here because the run plan depends on whether they land. All are
export-only — no change to the wire format, the measured window, or the signed
evidence.

1. **Export `attester_rtt0_ns` and `attester_rtt1_ns` per observation.**
   `ProbePairResult` already carries both; this is a `cmd/attester` logging
   change only.
2. **Export `attester_turnaround_ns`** (kernel arrival of reply 0 →
   immediately before `Sendto` of probe 1). Needs `probePairChallenged` and
   `sendAndRecv`/`tryRecv` to surface two locals into `ProbePairResult`.
   With it, `anchor_measured_rtt_ns − attester_turnaround_ns` is the
   anchor-send-plus-kernel residue, and the decomposition the brief asks
   about becomes computable per pair.
3. **Nanosecond observation timestamps** (`time.RFC3339Nano` in `now()`),
   so within-run drift and autocorrelation can be computed against real time
   rather than sequence number.
4. (Deferred, noted in the program README: exporting kernel *and* userspace
   receive stamps per observation folds the kernel-vs-userspace question into
   this experiment's analysis later. Not required for this run.)

If the branch lands before collection, the pinned commit below changes to the
branch commit and the decomposition analyses in `analysis/PLAN.md` activate.
If not, this run reports combined costs only, and the pinning axis is the only
decomposition.

## Pinned versions

| | |
|---|---|
| Plugin | `location-proofs/plugin-rtt-anchor` |
| Commit | `a1a1133015fe75ffee286fe5955b76ad2482586d` — **provisional**: current `main` HEAD at design time (working tree clean); re-pin at run time, especially if the export branch lands |
| Built with | Go ≥ 1.25.0 (module requirement in `go.mod`); record exact `go version` output at build time |
| Build command | `GOOS=linux GOARCH=amd64 go build -o anchor ./cmd/anchor` and `GOOS=linux GOARCH=amd64 go build -o attester ./cmd/attester` |

Binaries are statically linked and cross-compiled locally; no toolchain exists
on the hosts.

## Environment

| Host | Role | Location | Notes |
|---|---|---|---|
| `hap-gpu` (`testbed-node1`) | anchor + attester, loopback | Cambridge, UK (52.20653, 0.12018, operator-asserted) | Bare metal, Threadripper PRO 3945WX 12c/24t, single NUMA node, 247 GiB RAM, Ubuntu 26.04, kernel 7.0. Five RTX 3090s power-capped to 200 W (caps are the operator's; untouched). **Shared machine**: work under `~/johnx/`, no sudo, named tmux, load experiments announced beforehand — conventions in `../infra/hap-cluster.md` bind. |
| `hap-server` (`ubuntu-2gb-hel1-1`) | anchor + attester, loopback (contrast only) | Hetzner `hel1` (60.34329, 25.02972) | KVM, **1 vCPU** EPYC-Genoa, Ubuntu 26.04. Anchor and attester must share the core while the attester busy-polls, so this run is contention-inflated **by construction**. |

Environment facts that could plausibly move the result, and how each is
handled:

- **Other users' load on `hap-gpu`.** Cannot be controlled, only observed.
  The run is announced beforehand per cluster convention; host-state
  snapshots before and after every cell record load average, top processes,
  and GPU utilization, and a cell whose snapshots show foreign load is
  flagged, not repaired.
- **CPU frequency scaling and governor.** Unknown until surveyed, and not
  changeable without sudo. Snapshotted per cell (governor, current
  frequencies); whether it moves the floor is an outcome of the pinning and
  load contrasts, not an assumption. **Needs investigation at run time.**
- **Clock discipline.** The signed interval is a CLOCK_REALTIME difference
  (see Clock domains). Snapshot `timedatectl` and the current clocksource per
  cell; on `hap-server` note the KVM clocksource. Chrony state may not be
  readable without privileges — record the failure if so.
- **Loopback timestamping semantics.** We assume loopback `SO_TIMESTAMPNS`
  stamps are taken at the same point in the delivery path as NIC-path stamps.
  **Needs investigation** (kernel-source reading of the `lo` transmit path
  would answer it); until then it is an explicit caveat on comparing this
  run's numbers against cross-host runs.
- **The `hap-server` contrast is kept deliberately.** What it means: an upper
  bound on self-noise for the actual production anchor host, and a validation
  that the pipeline runs there. What it does not mean: a floor, or a
  measurement comparable to `hap-gpu`'s — one busy-polling process starves
  the other on a single vCPU. Two cells only.
- The production anchor may already be listening on 8924/UDP on `hap-server`;
  the contrast run uses port 8925 and its own key and allowlist under a user
  directory. No firewall change is needed anywhere — loopback traffic does
  not traverse ufw's default input policy for `lo`. **Check at run time**
  that 8924 is free on `hap-gpu` (nothing else should hold it, but the
  machine is shared).

## Method

### Design decisions, with reasons

- **Pairs per cell: 5,000.** Tail quantiles are the expensive part: p99.9
  gets ~5 expected exceedances at 5,000 pairs, enough to estimate it with a
  bootstrap CI wide enough to be honest, and prior data (186 µs median on a
  VPS; 1% of sleeps overshooting 1 ms on the Hetzner pair) says the
  interesting structure is in p99-p99.9. If the first cell's bootstrap CIs on
  p99.9 are unusably wide, raise the count before running the matrix and
  record the change under Deviations.
- **Spacing: 100 ms between pairs** (`-interval 100ms`; the attester sleeps
  this long after each pair completes, so effective spacing is ~100 ms plus
  the pair duration). Long relative to scheduler quanta and Go GC cycles, so
  consecutive pairs do not share a scheduling state by construction; short
  enough that a cell takes ~8.5 minutes. Spacing as an experimental axis is
  005's question, on the network path; it is fixed here, and autocorrelation
  at this spacing is checked in analysis rather than assumed away.
- **Rate limiting disabled** with `-verify-interval 0`. The reflector skips
  the rate-limit branch entirely when the interval is zero
  (`reflector_linux.go:228`); no other behavior reads the flag. This deviates
  from the production default of 29 s and is what makes bursts possible.
- **Warm-up: the first 50 pairs of every cell are excluded from summary
  statistics** by pre-registered rule (raw data keeps everything; analysis
  applies the cut and reports a sensitivity check). Binary start, key load,
  allowlist read, and first-touch page faults have no business in a
  steady-state characterization.
- **Load generator: plain busy loops** (`yes > /dev/null`, one per target
  thread), not `stress-ng` — no installs are permitted on the shared host,
  and a busy loop is exactly reproducible from the command line. Two levels:
  12 loops (half the SMT threads) and 24 loops (all of them). Stated
  limitation, per the brief: this exercises run-queue pressure only, and does
  not represent training load; that axis is 008's.
- **Pinning via `taskset`** on whole processes. "Separate" pins anchor and
  attester to two cores chosen from different L3 complexes (pick after
  reading `lscpu -e` on the host — **needs the run-time survey**; record the
  chosen cores); "same" pins both to one core, which is the deliberate
  worst case and the coarse stand-in for the `hap-server` situation.
- **Challenged is the default; two unchallenged cells** give the challenge
  delta at idle and under full load — enough to see whether the delta is
  load-sensitive (which would complicate calibrating it away as a constant)
  without doubling the matrix.
- **Two replications of the full `hap-gpu` matrix on different days.** One
  replication cannot distinguish a stable floor from a lucky afternoon.
- **`-raw` is on everywhere.** The anchor-signed bytes are the evidence;
  everything else is a reading of them (`../infra/README.md` § Collecting).
- **GC visibility:** run both binaries with `GODEBUG=gctrace=1` and keep
  stderr, so Go garbage-collection pauses can be checked against tail
  excursions instead of speculated about. Stdout (the JSONL) is unaffected.

### Condition matrix

Cells 1-9 on `hap-gpu`, run twice (rep A and rep B, different days).
Cells 10-11 on `hap-server`, run once.

| Cell | Host | Challenge | Load | Pinning |
|---|---|---|---|---|
| 1 | hap-gpu | on | idle | unpinned |
| 2 | hap-gpu | on | idle | separate cores |
| 3 | hap-gpu | on | idle | same core |
| 4 | hap-gpu | on | 12 busy loops | unpinned |
| 5 | hap-gpu | on | 12 busy loops | separate cores |
| 6 | hap-gpu | on | 24 busy loops | unpinned |
| 7 | hap-gpu | on | 24 busy loops | separate cores |
| 8 | hap-gpu | off | idle | unpinned |
| 9 | hap-gpu | off | 24 busy loops | unpinned |
| 10 | hap-server | on | as-found | unpinned |
| 11 | hap-server | off | as-found | unpinned |
| 12 (optional, John's call) | hap-gpu | on | 1-GPU synthetic training | unpinned |

Cell 12 exists only to spot-check whether synthetic CPU load is a usable proxy
for real load before 008; it needs a workload defined (not designed here) and
is struck without prejudice if that is more instrument-building than the check
is worth.

At 5,000 pairs per cell and ~8.5 minutes per cell, the full plan is 20
captures ≈ 3 hours of capture time plus setup, spread over two days.

### Steps

1. On the laptop: check out the pinned commit, build both binaries with the
   exact commands above, record `go version` and the binary SHA-256s.
2. Copy the binaries to `hap-gpu:~/johnx/experiments/001-host-jitter/`.
3. Announce the load experiment to the cluster's users (convention in
   `../infra/hap-cluster.md`); check `nvidia-smi` and `who` for active work.
4. Survey once per host and save to `data/`: `lscpu -e` (choose and record
   the pinning cores), governor files, clocksource, `timedatectl`, kernel
   version, exact binary hashes.
5. Generate keys (anchor and attester key files under the working directory),
   write the attester's public key into the anchor's allowlist file.
6. Start the anchor in a named tmux session with the exact command below.
   It stays up across all cells of a given pinning condition; it is restarted
   (with `taskset` as required) when the pinning condition changes, and the
   restart is recorded.
7. For each cell, in order, via the harness script (one cell = one
   invocation): take the pre snapshot, start the load loops (if any), run the
   attester for 5,000 pairs with the cell's flags, stop the load loops, take
   the post snapshot. Snapshots and stderr logs land in `data/` next to the
   capture.
8. Between rep A and rep B: at least one day's separation; repeat step 3.
9. `hap-server` cells: same procedure on port 8925, no load generator, after
   confirming the production anchor is undisturbed.
10. Copy `data/` back to the repository, commit raw captures unmodified.

## Commands

Anchor (hap-gpu; prefix with `taskset -c <core>` for pinned cells):

```sh
GODEBUG=gctrace=1 ./anchor \
  -id anchor-loopback-hapgpu \
  -lat 52.20653 -lng 0.12018 \
  -listen 0.0.0.0:8924 \
  -key anchor-key.json \
  -allowlist allowlist.txt \
  -verify-interval 0 \
  2> data/<cell>-anchor.stderr.log
```

Attester, one cell (hap-gpu; add `taskset -c <core>` for pinned cells and
`-unchallenged` for cells 8, 9, 11):

```sh
GODEBUG=gctrace=1 ./attester \
  -anchor 127.0.0.1:8924 \
  -anchor-key <anchor public key hex> \
  -key attester-key.json \
  -json -raw \
  -interval 100ms \
  -count 5000 \
  -timeout 2s \
  >> data/<cell>.jsonl \
  2> data/<cell>-attester.stderr.log
```

Load generator, per level (12 or 24 loops; record PIDs, kill after the cell):

```sh
for i in $(seq 1 <N>); do yes > /dev/null & done
```

Host-state snapshot, before and after every cell:

```sh
{
  date -u +%FT%T.%NZ
  cat /proc/loadavg
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c
  grep MHz /proc/cpuinfo | sort | uniq -c
  cat /sys/devices/system/clocksource/clocksource0/current_clocksource
  timedatectl 2>&1
  nvidia-smi --query-gpu=index,utilization.gpu,power.draw,memory.used --format=csv 2>&1
  ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -25
  who
} > data/<cell>-{pre|post}.snapshot.txt
```

`hap-server` cells substitute `-listen 0.0.0.0:8925` / `-anchor
127.0.0.1:8925`, the host's own coordinates (`-lat 60.34329 -lng 25.02972`),
and omit the GPU query.

Cell naming: `<host>-<rep>-<chal|unchal>-<idle|cpu12|cpu24>-<unpin|sep|same>`,
e.g. `hapgpu-a-chal-idle-sep.jsonl`.

## Output

| What | Where |
|---|---|
| Raw per-pair JSONL, one file per cell (with `-raw` evidence bytes) | `data/<cell>.jsonl` |
| Host-state snapshots, pre and post per cell | `data/<cell>-{pre,post}.snapshot.txt` |
| Binary stderr incl. `gctrace` lines | `data/<cell>-{anchor,attester}.stderr.log` |
| One-time host surveys (lscpu, hashes, toolchain) | `data/survey-<host>.txt` |

Each JSONL line is one observation (~2 KB with `-raw`; two base64 reply blobs
of ~600 characters dominate). Expect 5,000 lines ≈ 10 MB per cell and roughly
200 MB total raw for the full plan. Timeouts and errors appear as JSONL lines
with an `error` field and no measurement; they are data (loss rate under
load), not noise to filter.

## Deviations

None yet — this section is written during the run. The known-in-advance
deviations from production defaults are recorded above by design:
`-verify-interval 0`, loopback addressing, port 8925 on `hap-server`, and
`GODEBUG=gctrace=1`.
