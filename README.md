# Experiments

Reproducible experiments benchmarking the [location-proofs](https://github.com/location-proofs)
plugin family.

Plugins produce evidence. This repository establishes what that evidence is
actually worth — how accurate, at what cost, under what conditions — by running
measurements and recording them in a form somebody else can re-run.

The plugins themselves live in their own repositories and stay clean libraries.
Everything environment-specific belongs here: provisioning, host quirks, campaign
configuration, raw captures, and findings.

## The pattern

One directory per plugin. Numbered experiments inside it.

```
plugin-rtt-anchor/
  README.md                    index of experiments for this plugin
  infra/                       how to stand up the testbed
  001-burst-convergence/
    RUN.md                     the reproducibility contract
    REPORT.md                  what we found
    harness/                   scripts that collect
    data/                      raw captures
    analysis/                  scripts that turn data into numbers
```

Each experiment directory is self-contained. It names the plugin commit it ran
against, so it can be re-run in six months without archaeology.

## Reproducing an experiment

Change into the experiment directory and read `RUN.md`. It pins the plugin
commit, names the hosts, and gives the exact commands. Nothing else should be
needed.

If `RUN.md` is insufficient to re-run the experiment, that is a bug in `RUN.md`.

## Adding an experiment

```sh
./new-experiment.sh plugin-rtt-anchor burst-convergence
```

This finds the next free number in that plugin's directory, copies `TEMPLATE/`
into place, and prints the path. Fill in `RUN.md` before collecting anything —
writing down the method first is what stops an experiment from drifting into
whatever the data happened to support.

## Adding a plugin

Create a directory named exactly as the plugin repository, give it a `README.md`
following the shape of an existing one, and add `infra/` if the plugin needs a
testbed. Nothing else is required.

## Conventions

These are load-bearing, and they are the whole reason the repository is
navigable.

- **Numbering is zero-padded to three digits** — `001`, `002`. Numbers are never
  reused, even if an experiment is abandoned. A gap is information.
- **Slugs are kebab-case** and describe what is being measured, not the
  conclusion. `burst-convergence`, not `bursts-are-enough`.
- **`data/` holds raw captures and is never edited by hand.** If a capture is
  wrong, discard it and re-run — do not repair it. Hand-edited data is not
  evidence.
- **`analysis/` holds scripts that turn data into numbers.** Analysis must be
  re-runnable against the raw data. A number that exists only in someone's
  terminal history does not count.
- **`REPORT.md` is the only place conclusions live.** Not in commit messages, not
  in code comments, not in `RUN.md`. One place to look.

## Where questions come from

Each plugin repository carries its own record of what is unknown. For
`plugin-rtt-anchor` that is
[`docs/open-questions.md`](https://github.com/location-proofs/plugin-rtt-anchor/blob/main/docs/open-questions.md),
where every question ends with what would settle it.

Experiments here exist to close those questions. The link runs both ways: an
experiment names the question it answers, and a question should eventually name
the experiment that settled it.
