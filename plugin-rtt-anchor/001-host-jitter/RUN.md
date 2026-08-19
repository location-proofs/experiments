# Run: [experiment name]

The reproducibility contract. Fill this in before collecting anything.

## Question

[One sentence. What do we not know?]

**Open question:** [§X.Y in the plugin's docs/open-questions.md, with a link]

## Pinned versions

| | |
|---|---|
| Plugin | `location-proofs/[plugin-name]` |
| Commit | `[full SHA]` |
| Built with | [toolchain and version, e.g. go1.25.5] |
| Build command | [e.g. GOOS=linux GOARCH=amd64 go build ./cmd/...] |

An experiment that does not name its commit cannot be re-run. If the run needed
an unmerged change, say so here and link the branch or patch.

## Environment

| Host | Role | Location | Notes |
|---|---|---|---|
| [hostname] | [anchor/attester] | [site, coordinates] | [virtualization, CPU, anything that affects timing] |

[Anything about the environment that could plausibly change the result: load,
co-tenancy, firewall rules, clock, network path. If you had to change host
configuration to run this, record the change.]

## Method

[Numbered steps. Enough that someone else runs the same experiment, not a
description of what you did once.]

1. [step]
2. [step]

## Commands

```sh
[Exact commands, copy-pasteable. Include flags in full — an abbreviated command
is not a record.]
```

## Output

| What | Where |
|---|---|
| [raw capture] | `data/[filename]` |

[Format of the raw output, and roughly how much of it to expect.]

## Deviations

[Anything that differed from the plan, and why. Empty is a valid answer, but
write "None" rather than deleting the section — a missing section reads as an
omission.]
