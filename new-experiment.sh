#!/usr/bin/env bash
# Scaffold a new experiment directory from TEMPLATE/.
#
# Usage: ./new-experiment.sh <plugin> <slug>
#    eg: ./new-experiment.sh plugin-rtt-anchor burst-convergence
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="${1:-}"
slug="${2:-}"

if [[ -z "$plugin" || -z "$slug" ]]; then
    echo "usage: $0 <plugin> <slug>" >&2
    exit 1
fi
if [[ ! -d "$root/$plugin" ]]; then
    echo "no such plugin directory: $plugin" >&2
    echo "create it first, with a README.md following an existing one" >&2
    exit 1
fi
if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "slug must be kebab-case: $slug" >&2
    exit 1
fi

# The number is always fresh, so the only real collision is a repeated slug.
existing=$(ls -d "$root/$plugin"/[0-9][0-9][0-9]-"$slug" 2>/dev/null || true)
if [[ -n "$existing" ]]; then
    echo "an experiment with this slug already exists: ${existing##*/}" >&2
    exit 1
fi

# Numbers are never reused, so take the highest and add one rather than
# filling gaps. A gap records an abandoned experiment.
last=$(ls -d "$root/$plugin"/[0-9][0-9][0-9]-* 2>/dev/null \
    | sed 's|.*/||' | cut -d- -f1 | sort -n | tail -1 || true)
next=$(printf '%03d' $(( 10#${last:-0} + 1 )))
dir="$root/$plugin/$next-$slug"

mkdir -p "$dir"/{harness,data,analysis}
touch "$dir"/{harness,data,analysis}/.gitkeep
cp "$root/TEMPLATE/RUN.md" "$root/TEMPLATE/REPORT.md" "$dir/"

echo "$dir"
echo "fill in RUN.md before collecting anything."
