# Design prompt: 008-gpu-load

When the machine is doing the work we actually want to locate — training — what
happens to the measurement's timing and to its availability?

This is a design brief, not a design. Challenge the framing where it is wrong,
separate known from assumed from unknown, and write "needs investigation"
rather than inventing answers. This experiment deliberately runs **last**: it
depends on 001 (host floor under first load increments), 002 (signing cost),
and above all 007 (where signing happens — a GPU-side signer under load is a
different experiment from a CPU signer under load). Deliverable: a draft
`RUN.md` whose method is explicitly conditioned on 007's outcome, with the
CPU-signer variant designed concretely now, for John's review. Do not run
anything against any host.

## The question

The class of machine this method most wants to locate is a GPU host that is
actually working — and that is the state hardest to measure in. Two separable
questions:

1. **Timing.** Training is not GPU-only: it loads CPU cores (dataloaders,
   kernel-launch threads), memory bandwidth, and PCIe, and the attester's
   turnaround runs on exactly those CPUs — inside the anchor-measured window.
   How do the turnaround's floor and tail move as the machine steps from idle
   to saturated? (First increment already lives in 001's condition matrix;
   this experiment is the full treatment over the real path.)
2. **Availability.** What fraction of challenges complete within timeout
   during sustained training, and how does the effective probe budget shrink?
   If a GPU-side signer (007) needs the GPU, what is the queueing delay when
   all SMs are busy — does signing need the GPU "free," and what does "free"
   even mean here (stream priorities, MPS, preemption)? Needs investigation;
   do not assert CUDA scheduling behavior from memory.

## Why it matters — the security frame (from `../research-program.md`)

Soundness survives load: noise is one-sided, so a loaded host only ever looks
farther away, and the max-distance bound holds. The risks are subtler, and the
measurements here are what make them arguable in either direction:

- If challenges degrade or fail under load, honest evidence clusters in idle
  windows — a verifier must then choose between sparse, prover-timed evidence
  (the §3.1 cherry-picking surface) and rejecting honest busy machines.
- Load-dependent failure hands an uncooperative operator deniability: "we were
  training" and "we chose not to answer" produce the same evidence stream.

## What we know (with sources)

- Five RTX 3090s, independently addressable, power-capped to 200 W — load can
  be stepped 0→5 GPUs in controlled increments (`../infra/hap-cluster.md`).
  Performance figures from this box do not generalize to uncapped cards; say
  so wherever throughput matters.
- Shared machine: load experiments are announced beforehand, GPUs are pinned
  with CUDA_VISIBLE_DEVICES, other users' containers may hold GPUs at any
  moment — check before claiming (`../infra/hap-cluster.md`).
- 001's conditions will already have produced loopback turnaround data under
  some GPU load; this experiment extends to the WAN path and to availability,
  where timeouts and the anchor's rate limit interact.

## What we assume (unverified)

- That a representative "training load" can be constructed honestly. A real
  training loop (which framework? what model size? dataloader workers?) and a
  synthetic saturator stress different resources; the choice shapes the
  result. Treat workload realism as a first-class design question, and record
  the workload precisely enough to reproduce it.
- That challenge failures under load are observable and attributable in the
  JSONL (timeouts appear as error records — verify against
  `cmd/attester/main.go` — but distinguishing attester-side from anchor-side
  from path losses needs thought).

## What we don't know

- Almost everything about the GPU-signer-under-load case until 007 lands —
  leave it as a conditioned section, not a designed one.
- Whether availability should be measured against the production rate limit or
  a testbed one; the answer changes what the result means for real
  deployments. Argue it, don't assume it.
