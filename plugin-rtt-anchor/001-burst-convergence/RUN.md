# Run: burst convergence

The reproducibility contract. Fill this in before collecting anything.

## Question

How many probes does a burst need before the minimum stops improving?

**Open question:** [§1.1 How many probes does a burst need?](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md)

The estimator is `min` over a burst, because network noise is one-sided. What is
unknown is the rate of convergence, which is what converts probes into accuracy
and therefore sets the operating point for everything else.

## Pinned versions

| | |
|---|---|
| Plugin | `location-proofs/plugin-rtt-anchor` |
| Commit | `[fill in]` |
| Built with | `[fill in — go version]` |
| Build command | `GOOS=linux GOARCH=amd64 go build -o attester ./cmd/attester` |

## Environment

| Host | Role | Location | Notes |
|---|---|---|---|
| `geobeat-ingest` | anchor | `hel1-dc2`, 60.2934, 25.0378 | KVM, 8 vCPU, runs other workloads |
| `xo-server` | attester | `fsn1-dc8`, 50.4779, 12.3713 | KVM, 2 vCPU, runs other workloads |

Ground truth for this path is 1,348 km. See [`../infra/`](../infra/) for the full
testbed record and baseline jitter figures.

Both hosts carry unrelated production load. That is the realistic case, but it
means the result is a floor for these hosts rather than for the path — separating
host jitter from network jitter is §1.3's job, not this one.

Record actual load at run time, since it is the most likely confound.

## Method

1. Open `8924/udp` on the anchor and start it with a rate limit low enough not to
   throttle the burst. The default `-verify-interval` of 29 s would stretch
   10,000 pairs across roughly 80 hours.
2. Enrol the attester's key in the anchor's allowlist.
3. Run one burst of 10,000 pairs at fixed 20 ms spacing, capturing JSONL.
4. Repeat at three times of day — suggested 03:00, 12:00 and 20:00 UTC — since
   the convergence rate may itself be load-dependent.
5. Bootstrap-subsample each capture at N = 1, 2, 5, 10, 20, 50, 100, 500 and plot
   the distribution of `min(N)` against N.

Spacing is held fixed at 20 ms throughout. Whether spacing changes what you learn
is §1.2, and varying both at once would confound them.

Run the whole thing in both directions if time allows. Routing is often
asymmetric, and the reverse path is a free second sample.

## Commands

On the anchor:

```sh
sudo ufw allow 8924/udp

./anchor \
  -id anchor-hel-1 \
  -lat 60.2934 -lng 25.0378 \
  -listen 0.0.0.0:8924 \
  -key anchor-key.json \
  -allowlist allowlist.txt \
  -verify-interval 10ms
```

On the attester, once its key is enrolled:

```sh
./attester -print-key   # enrol this on the anchor first

./attester \
  -anchor <anchor-host>:8924 \
  -anchor-key <anchor public key> \
  -interval 20ms \
  -count 10000 \
  -json -raw \
  > data/burst-YYYYMMDD-HHMM.jsonl
```

At 20 ms spacing a 10,000-pair burst takes a little over three minutes.

## Output

| What | Where |
|---|---|
| Raw observations, one JSON object per line | `data/burst-YYYYMMDD-HHMM.jsonl` |
| Subsampling analysis | `analysis/` |

Expect roughly 10,000 lines per capture. With `-raw` each record carries the
base64 anchor-signed reply bytes, so files run to a few megabytes.

The field to analyse is `anchor_measured_rtt_ns`. It arrives inside the anchor's
signature, so it is the number a verifier could rely on;
`attester_measured_rtt_ns` is self-reported and is a sanity check only.

## Deviations

[None yet — the run has not happened.]
