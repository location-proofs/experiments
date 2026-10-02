# Falkenstein anchor, HAP campaign (archived)

Raw files pulled from the Falkenstein anchor host before it was decommissioned.
They are not tied to a numbered experiment and have no `RUN.md`; treat them as
an archive, not as evidence for any report.

- **Host:** Hetzner `ubuntu-2gb-fsn1-1`, `167.235.203.200` (data center `fsn1`, Falkenstein)
- **Collected by:** Ryan Bevin's HAP branch campaign, 2026-08-20 to 08-21
- **Archived:** 2026-10-02, SHA-256 checked against the host

## Contents

- `ryanb/`: `/home/ryanb/location-proofs/` (measurement JSONs, anchor allowlist)
- `root/`: `/root/location-proofs/` (an earlier anchor log and allowlist)

Binaries (`anchor`, `attester`) and signing keys (`*-key.json`) were left out.
So was `ryanb/anchor_falkenstein.log` (15 MB, 108,408 `DEBUG` lines). Its only
`INFO` lines record the anchor that produced the `ryanb/` measurements:

- Started `2026-08-21T11:52:16Z`, 3 allowed attesters
- Public key `cfe4d7d01ed2c8b85a3f1a584a1076d882a4412d5f0485a5a894d63b559ad89a`

The earlier anchor in `root/anchor_falkenstein.log` used a different key
(`12a157c3…`) and ran 2026-08-20 10:26–11:06 UTC.

## Caveats

- The anchor ran with `-lat 50.2163 -lng 8.451`, which is near Frankfurt. The host
  is in Falkenstein (roughly 50.48, 12.37), so any bound derived from these
  coordinates is off by about 300 km.
- This host is not in the testbed record (`../../README.md`), which names
  `xo-server` as the Falkenstein anchor.
