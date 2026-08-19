# Design prompt: 007-signing-placement

Where can the nonce signature physically happen — and what does each placement
cost in time and mean for security?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. This experiment is explicitly *blocked on input*
(a collaborator's in-progress branch); designing around guesses about that
branch is the failure mode to avoid. Deliverable: a draft `RUN.md` with the
placement taxonomy, the measurable questions per placement, and clearly-marked
blocked sections, for John's review. Do not run anything against any host.

## The question

Today the nonce that arrives from the anchor is signed in userspace, on the
CPU, with a software-held Ed25519 key — the GPUs are entirely outside the loop.
But the point of the method is locating *GPUs*, so where the signature happens
is both a timing question (the signature sits inside the anchor-measured
window; every microsecond is ~150 m) and a security question (what does a
signature from placement X actually prove, and what can an attacker at
placement X−1 forge?). Candidate placements to reason about: the current
in-process CPU signer; a separate process or daemon; a GPU kernel with the key
in VRAM; a TEE/confidential-computing enclave on future hardware.

## What we know (with sources)

- The current implementation: `Ed25519Signer` in the attester process
  (`~/code/plugin-rtt-anchor`, `internal/signed/packet.go`, used from
  `sender_linux.go`). The plugin's `docs/gpu-binding.md` describes the two-loop
  construction and why anything slow cannot sit inside the timing loop.
- This testbed's GPUs (RTX 3090, consumer Ampere) have **no confidential
  computing**, confirmed directly; the CPU is Zen 2, no SEV-SNP
  (`../infra/hap-cluster.md`). So on this hardware a GPU placement protects
  the key not at all — its value is *pricing the placement*: if even an
  unprotected CUDA signing path blows the timing window, the secured version
  on Hopper-class hardware is dead on arrival, and that is worth knowing
  cheaply. Do not overclaim in the other direction either: a fast unprotected
  path does not prove the CC-enabled path is fast.
- **John's collaborator has an in-progress branch "calling down to the GPU to
  sign"; its state is unknown.** The design must request and read that branch
  before committing to a GPU-side method. Mark every section that depends on
  it as blocked rather than speculating.
- Five 3090s, power-capped to 200 W, shared machine — GPU work must be pinned
  and announced (`../infra/hap-cluster.md`).

## What we assume (unverified)

- That kernel-launch latency plus PCIe round trip is the dominant cost of a
  GPU placement (plausible; unmeasured on this box, and the power caps and
  PCIe-only peering make external figures unreliable here).
- That an Ed25519 implementation suitable for in-kernel (CUDA) execution
  exists or is buildable at reasonable effort — this may be exactly what the
  collaborator's branch answers.

## What we don't know

- The security taxonomy in detail: for each placement, what the signature
  attests, the extraction/forgery story, and what binding to *the machine* vs
  *the GPU* vs *the enclave* each provides. This is analysis work as much as
  measurement work — scope it as such, and keep it separate from the timing
  measurements so neither contaminates the other.
- Whether placement changes require plugin modifications (the `Signer`
  interface in `packet.go` looks like the seam — verify) and how to keep any
  experimental signer out of the clean library per the repo split.
- How this composes with 008: a GPU signer on a busy GPU is 008's subject;
  this experiment should produce the idle-case placement costs 008 will load.
