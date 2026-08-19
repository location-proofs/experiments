# HAP cluster — node1 survey

Surveyed 2026-08-19 over SSH, read-only. **This documents `testbed-node1` only**
(the host aliased `hap-gpu` in [`README.md`](README.md)). The cluster has at
least one more node — a machine at `10.10.10.2` on the InfiniBand fabric answers
SSH but rejects the `felkru` credentials held on node1 — and nothing below
should be assumed to apply to it.

This is a shared experimental machine operated by others. Conventions for
working on it are at the end; they are load-bearing.

## Identity and access

| | |
|---|---|
| Hostname | `testbed-node1` |
| LAN address | `192.168.80.80/24` (1 GbE) |
| Tailscale | `100.105.22.23` — reachable off-LAN |
| InfiniBand | `10.10.10.1/24`, 100 Gb/s, ConnectX-6, link active to `10.10.10.2` |
| Account | `felkru` — shared; has `sudo` and `docker` group |
| SSH alias | `hap-gpu` (key `hap-gpu-cluster_ed25519`) |

The `felkru` account is a shared identity: as of the survey its
`authorized_keys` held three keys (the operator's workstation, `lenny`, and
`johnx`). Anything run under it is attributable only to the account, not to a
person — process names, tmux session names, and working directories are the
only way to tell whose work is whose.

## Hardware

| | |
|---|---|
| CPU | AMD Threadripper PRO 3945WX — 12 cores / 24 threads, Zen 2, up to 4.4 GHz, single NUMA node |
| RAM | 247 GiB (plus 8 GiB swap) |
| GPUs | 5× NVIDIA RTX 3090, 24 GiB each — 120 GiB VRAM total |
| GPU links | PCIe gen4 x16 per card; no NVLink; all peer-to-peer traffic crosses the host bridge |
| Storage | 1 TB Samsung 9100 PRO NVMe, single volume, ~808 GiB free at survey. No scratch array, no network filesystem |

**Every GPU is power-capped to 200 W** against defaults of 350–420 W — a
deliberate site decision (five uncapped 3090s draw ~2 kW). Expect roughly
two-thirds of nominal sustained throughput, and do not treat performance
figures from this box as representative of unconstrained 3090s. The caps are
the operator's call; leave them alone.

## Software

Ubuntu 26.04 LTS, kernel 7.0. NVIDIA driver 595.84 (CUDA 13.2 runtime) with
CUDA toolkit 12.4 (`nvcc`). Python 3.14, Docker 29, git, tmux. No conda, uv,
Go, or Rust toolchains — the attester binary is cross-compiled locally and
copied across (see [`README.md`](README.md) § Building), and anything else goes
in a venv under one's own directory.

## No hardware root of trust — confirmed

Checked directly rather than assumed, per `docs/gpu-binding.md` in the plugin
repository:

- `nvidia-smi conf-compute -f` reports `CC status: OFF`, and it can never be
  on: consumer Ampere has no confidential-computing support.
- The CPU is Zen 2 — `/proc/cpuinfo` shows `sev` and `sev_es` only, no
  SEV-SNP. That needs Zen 3 or later.

So neither the GPUs nor the CPU can anchor the two-loop construction, and the
`gpu-attestation` experiment is hard-blocked on this hardware. What the node
*can* do honestly is run the fast loop with a software-held key — a binding to
a host, not to silicon — and serve as a controllable-load attester host, which
is its actual role in the testbed.

## What it is good for

- **Controlled load generation.** Five independently addressable GPUs that can
  be saturated on demand make it the right machine for §1.3 (host-jitter): run
  the timing loop while stepping the machine from idle to saturated.
- **Quiet-host baseline.** Essentially idle most of the time (load 0.03 at
  survey), unlike the Hetzner pair.
- **Sustained availability.** Bare metal, up for days, reachable over
  Tailscale.
- **A sleeper: the InfiniBand fabric.** 100 Gb/s to a second node gives
  microsecond-scale, near-deterministic RTTs — a potential clean-room for
  timing-loop work with network noise almost removed, if access to node2 ever
  materialises.

Not good for: attestation experiments (no TEE), representative GPU benchmarks
(power caps), or large multi-GPU training (PCIe-only peering, 12 CPU cores).

## Shared-use conventions

There is no job scheduler. Coordination is social, and these are the agreed
rules for the `johnx` presence on the box:

- All work lives under `~/johnx/`. Nothing outside it is created, modified, or
  deleted.
- No `sudo`, no system package installs, no changes to GPU power caps or
  clocks, no editing shared configuration.
- Check `nvidia-smi` before claiming a GPU, and pin work with
  `CUDA_VISIBLE_DEVICES`. The GPUs being idle at a glance does not mean they
  are free: other users' containers (two `mentee-robi*` containers were up at
  survey) can claim them at any time.
- Never touch processes or containers you did not start.
- Long-running jobs go under a named tmux session (`tmux new -s johnx`) with
  logs under `~/johnx/`, so nothing runs orphaned or anonymous.
- Multiple attester instances coexist without port collision — the attester is
  a pure UDP client on an ephemeral source port; the only fixed port in the
  system is the anchor's (8924/UDP, on the anchor hosts). What *does* collide
  is the default key path: `-key attester-key.json` is resolved relative to
  the working directory and generated if absent, so each user runs from their
  own directory with their own key file. Timing experiments that load the
  machine (§1.3 especially) are announced beforehand, since one user's load is
  another's confound.
