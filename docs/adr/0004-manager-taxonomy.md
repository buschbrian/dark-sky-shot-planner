# ADR-0004: Land-manager taxonomy

**Status:** accepted · **Date:** 2026-08-22

## Decision

PAD-US's managerial hierarchy is collapsed into eight readable classes,
defined in `config/app-config.json`: Federal – BLM, Federal – USFS,
Federal – NPS, Federal – other, State, Tribal, Private / undetermined,
Unknown.

## Alternatives considered

- **Pass PAD-US fields through raw** (`Mang_Name` has hundreds of values) —
  illegible on a map and in an answer panel.
- **Finer taxonomy (per-agency)** — better precision, worse legibility; the
  app's question is "can I legally stand here at 2 a.m.", which agency
  *family* answers far better than individual unit names.

## Reasoning

The normalization is conservative: unrecognized managers become `unknown`,
never a guess, because a wrong statement about land status is worse than an
honest gap. The taxonomy lives in config so extending it is a data change.

## Consequences

Adding an agency means adding markers in `pipelines/padus/taxonomy.py` and
a class entry in config. The client renders labels/colors from the same
config file, so map and text cannot disagree.
