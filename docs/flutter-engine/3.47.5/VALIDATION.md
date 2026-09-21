# Flutter 3.47.5 engine validation

Denial's Flutter 3.47.5 generation is a release-only engine upgrade. Debug and
profile engines were deliberately excluded from the upgrade and release path.

## Source identity

- Flutter upstream: `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`
- Flutter fork: `718ccf2c2314f6cac9808e5eb37d0117407eb4e4`
- Flutter branch: `denial/3.47.5-r1`
- Dart: 3.13.4 at `b530c21f7de367b94fb04787bfed9d8e989d75e8`
- Engine artifact revision: `af7e796e161ae0bb1ff0758c71a7105418bd9ded`
- Skia upstream: `8df24be66531469e576a806749a0202ae26b8d08`
- Skia fork: `5b495e3e15a59ee76af882d83316d351654c1e88`
- Skia branch: `denial/3.47.5-r1`

The Flutter fork contains 128 Denial commits directly on the 3.47.5 upstream
commit, with no merge commits. The Skia fork contains three Denial commits
directly on its coupled upstream commit, also with no merge commits. Both exact
fork tips were pushed and verified on their `denialwm` remotes before the
Denial source lock advanced.

## Generated ABI and release artifact

The official Flutter embedder bindings were regenerated and checked from the
3.47.5 upstream header. Denial's private embedder extension remains typed
separately in `compositor/flutter-engine/src/lib.rs`.

- Official embedder header SHA-256:
  `94122469b254a932394bb5bb5c625317426eefd6e23d4366e32372c70ac5be37`
- Denial fork embedder header SHA-256:
  `1c6b72beb8d1ded1c0c111974210efd1ae4b7c09ac595a0865158ef6f76a54ed`
- Generated Rust bindings SHA-256:
  `9a41a4c9032bac3a77afe0cac7e47eebff72cfa28a38c7ae5537fab75f625f81`
- Release `args.gn` SHA-256:
  `86190a142bf1d4283716e5c254bf9054db38430b8e089692760374bea6f75af3`
- Release engine SHA-256:
  `c11ed3e76dd771ceeee0b2104f5a5210c3cdd180db1d5ce5a79afdff833c765a`
- Release engine GNU build ID:
  `1e1b253d46bbb503264b4e198404e5870e969755`

The generated binding check passed, the native engine compiled, the Dart 3.13.4
AOT shell compiled, and the isolated ABI/AOT loader check passed. The complete
local release shell and Rust compositor also built successfully. Nix engine and
Pub locks were regenerated and verified against the same source lock. The
release-path suite passed 281 compositor tests, four Rust embedder tests, and
two portal tests without building a debug or profile engine.

## Hardware activation

The release engine and rebuilt Denial bundle were deployed to the agent-managed
host `192.168.1.188` as artifact
`718ccf2c2314f6ca-73c0cff61fba766a`. After restarting `greetd.service`, the new
`deniald` and portal processes were active. Independent process-map and file
hash checks confirmed that `deniald` mapped the deployed engine above and that
the compositor, shell, engine, and portal bytes matched the local artifacts.

Visual inspection remains user-owned. On 2026-09-22 the user confirmed that the
upgraded session works. No screenshot or agent-triggered visible test event was
used.
