# Release-candidate audit — 2026-07-19

## Verdict

**NOT READY**

The correctness and build changes in this repository are implemented and
covered, but release approval is blocked by two mandatory external outcomes:

1. Observer Protocol v1 is not present in hosted `all_observer` 1.5.6, so both
   packages still require the `protocol-v1` Git dependency.
2. Chrome ran the example successfully, but the extension panel was not
   exercised interactively inside a real Flutter DevTools host.

## Baseline (commit 7d48fcec705b490e6cf8c43466733a0d7842861f)

- Flutter 3.44.6, Dart 3.12.2, DevTools 2.57.0.
- Root: 37 tests passed; analyze failed on a Git dependency and one extension
  test lint; publish dry-run failed with three warnings and produced a 61 MB
  archive containing intermediate/nested builds.
- Extension: 14 tests passed; analyze failed on that lint; its standalone
  publish dry-run failed (source package is `publish_to: none`).
- `devtools_extensions validate`, the web release build, and the originally
  requested build command passed. The installed CLI later proved that its
  destination was one directory too deep and caused `build/build`.

## Hypotheses reproduced and corrections

| Hypothesis | Reproduction | Correction / result |
| --- | --- | --- |
| Streaming starts after the snapshot | Transport fake emits only after `setStreaming(true)`; old order failed | Subscribe, enable streaming, snapshot, poll backlog, merge/dedupe/sort by sequence/session; integrated real-batcher test passes |
| Concurrent resync loses/overwrites state | Rapid gaps, failing snapshot, obsolete protocol/snapshot responses | `_activeResync`, connection generation, logical cancellation, bounded attempts and `try/finally`; tests pass |
| Empty polling response has another schema | Registrar response failed complete-model expectations | Empty and non-empty polling now share version/session/range/events schema; registrar-to-client-to-model test passes |
| Payload uses character estimates | Unicode envelope and exact/one-byte-over tests | Complete candidate batch measured by `utf8.encode(jsonEncode(...)).length`; oversized singleton is dropped and counted |
| Registration hides all failures and captures old state | Injected success/duplicate/unexpected registries and old handler | Exact duplicate classification, sanitized failure map/log, static current-handler routing and status diagnostics |
| Decode errors disappear | Invalid version/session/type/range/field fixtures | Strict sanitized decoder, failure counter/log/UI diagnostic, stream stays alive and resync is requested |
| Package contains stale/duplicate artifacts | Dry-run archive inspection | `.pubignore`, correct CLI destination `--dest=../devtools`, nested build removed; final archive is 15 MB and contains one panel |

## Final automated evidence

- Root tests: **43 passed**.
- Extension tests: **24 passed**.
- Extension `flutter analyze`: **no issues**.
- Root `flutter analyze`: **one remaining warning**, the prohibited Git
  dependency.
- `flutter build web --release`: passed; Material and Cupertino font assets
  resolved; only informational tree-shaking/Wasm messages remain.
- `devtools_extensions build_and_copy --source=. --dest=../devtools`: passed.
- `devtools_extensions validate --package=../..`: **Extension validation
  successful**.
- Root publish dry-run: panel included, 15 MB archive; still fails for the Git
  dependency and dirty working tree. The dirty-tree warning disappears after
  an intentional commit; the Git warning requires an upstream release.
- Chrome smoke: example served HTTP 200 on Chrome 150 and the remote debugging
  target reported title `all_observer_devtools example`. This is not evidence
  that the DevTools extension panel itself was opened or exercised.

## Before / after

| Area | Before | After |
| --- | --- | --- |
| Connection window | Streaming enabled after snapshot; no backlog poll | Streaming enabled first; snapshot + backlog + live merge |
| Resync | Multiple untracked futures; stale results possible | Single-flight per generation; stale/disposed results ignored |
| Empty polling | Missing protocol/session fields | One stable batch schema |
| Payload cap | Per-event `String.length` estimate | Full-envelope UTF-8 hard cap |
| Oversized event | Could exceed configured cap | Dropped visibly with dedicated counter |
| VM registration | `catch (_)`, old closure | Explicit duplicate/failure handling, current bridge routing |
| Decode failure | Silent catch | Sanitized log/counter/diagnostic/resync |
| Package | 61 MB with intermediate/nested build | 15 MB with one compiled panel |
| CI | None | Runtime, extension, contracts, web/copy/validate, payload and publish jobs |

## Residual risks and release checklist

- [x] Snapshot/backlog/live-stream integrated test.
- [x] Single-flight and stale-generation tests.
- [x] Empty polling end-to-end contract.
- [x] UTF-8 exact-limit and oversized-event behavior.
- [x] Hot-restart handler routing test.
- [x] Strict decode fixtures and visible failure state.
- [x] Adapter compiles against locked packages.
- [x] Panel built, copied and validated.
- [x] CI added; stale/empty checked-in panel fails its build job.
- [ ] Publish Observer Protocol v1 in a numbered hosted `all_observer` release.
- [ ] Replace both Git dependencies with that hosted constraint.
- [ ] Re-run root analyze and publish dry-run from a clean commit.
- [ ] Open the panel in real Flutter DevTools and test isolate switching, hot
  reload/restart, disconnect/reconnect, app termination, incompatibility,
  sustained event load, scopes/disposes, warnings, values and redaction.

