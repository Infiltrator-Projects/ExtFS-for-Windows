# Roadmap

This document describes direction; exact support is defined by the released source and validation evidence.

## Current foundation

- maintain qualified read support and the explicitly bounded write/resize subset
- keep x64 and ARM64 package/build paths aligned
- retain fail-closed feature handling and filesystem-contract tests

## Near-term priorities

- strengthen production signing and installer qualification
- expand mutation coverage only where journaling, allocation and rollback semantics are understood
- keep portable and WDK validation tied to the exact released source

## Longer-term direction

- broaden ext4 feature support without weakening unsupported-feature rejection
- increase real Windows hardware/filesystem evidence across architectures

## Admission and completion

A roadmap item needs clear ownership and a credible validation path before it is treated as planned work. It is complete only when implementation, tests, user-visible behaviour and maintained documentation agree.
