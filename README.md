# all_observer_devtools

Opt-in Flutter DevTools integration for
[`all_observer`](https://github.com/CriandoGames/all_observer): a read-only
diagnostics bridge from the Observer Protocol to the Dart VM Service.

> **Status: runtime bridge only.** This release (`0.1.0`) ships the piece an
> app depends on and initializes — the Observer Protocol consumer, the
> `ext.all_observer.*` VM Service extensions, and the batched event
> transport. The Flutter Web DevTools extension panel (Overview / Nodes /
> Timeline / Dependencies / Scopes / Warnings) that reads this data is a
> separate, later release. Until then, `ext.all_observer.*` can be exercised
> manually from `dart:vm_service` or the DevTools "Extensions" debugger, but
> there is no visual panel yet.

## Installing

```yaml
dependencies:
  all_observer: <version>
  all_observer_devtools: <version>
```

Both go in `dependencies`, not `dev_dependencies` — `AllObserverDevTools` is
gated by `kReleaseMode` and an explicit `enabled` flag, not by which
dependency section it's listed under, so it is safe to ship in a release
build (see [Security](#security)).

## Initialization

```dart
import 'package:all_observer_devtools/all_observer_devtools.dart';

void main() {
  assert(() {
    AllObserverDevTools.initialize();
    return true;
  }());
  runApp(const App());
}
```

`initialize()` requires no `BuildContext`, no top-level widget, and no
Navigator integration. It is:

- a no-op in release builds, regardless of configuration;
- a no-op when `enabled: false`;
- idempotent — a second call while already initialized does nothing, even
  with a different config;
- safe across hot restart — the bridge re-registers cleanly even though the
  underlying VM Service extension names may already exist in the isolate.

### Configuration

```dart
AllObserverDevTools.initialize(
  config: const AllObserverDevToolsConfig(
    enabled: true,
    batchInterval: Duration(milliseconds: 100),
    maxBatchSize: 200,
    maxPayloadBytes: 1 << 20,
    eventBufferSize: 1000,
    includeValueSummaries: true,
    includeStackTraces: false,
    redactValue: null,
  ),
);
```

`includeValueSummaries`, `includeStackTraces`, and `redactValue` are
forwarded straight to `ObserverProtocolConfig.captureValues` /
`.captureStackTraces` / `.redactValue` — this package adds no
value-serialization policy of its own; it reuses the core's existing
type/redaction/truncation rules verbatim, and `redactValue` is only an extra
application-supplied policy layered on top of them.

## What it exposes

Six VM Service extensions, each under the `ext.all_observer.` prefix and
returning `{"success": true, "protocolVersion", "sessionId", "data": {...}}`
or `{"success": false, "error": {"code", "message"}}`:

| Extension | Purpose |
| --- | --- |
| `getProtocolInfo` | Protocol/package version and capability list, for version negotiation. |
| `getSnapshot` | The full current `ObserverProtocolSnapshot` — the authoritative base state a client reconciles events on top of. |
| `getEvents` | Buffered events with `sequenceNumber` greater than an optional `afterSequence` parameter. |
| `setStreaming` | Turns the live batch transport on/off (`enabled=true`/`false`). Off by default. |
| `clearBuffer` | Clears only this bridge's local batching buffer — never the core's own ring buffer. |
| `getStatus` | Session id, streaming flag, buffered/dropped event counts (core ring-buffer *and* transport-layer, tracked separately), last sequence number. |

Live events, once streaming is enabled, are posted as batches on the
`all_observer:events` VM Service extension stream — ordered by
`sequenceNumber`, never mixing two sessions in one batch, split further if a
batch would exceed `maxPayloadBytes`.

## Security

- Read-only: nothing in this package can mutate application state.
- Values are never serialized raw — only the `ObserverValueSummary` the core
  protocol already produces (type name, optionally a bounded/redacted
  display string). `toString()` is never called on arbitrary values by this
  package.
- Nothing leaves the device: all communication is local, over the Dart VM
  Service, between the running app and a connected DevTools client. No
  analytics, no telemetry, no upload.
- Inert without explicit opt-in: `enabled: false` (or a release build) means
  no consumer, no service extensions, no buffer growth.

## Limitations

- **No visual panel yet.** The Flutter Web DevTools extension UI is a
  separate, later release of this package.
- **No route/screen association.** By design — see the implementation
  spec's "fora do escopo" section. This will not change in a future MVP
  without a deliberate scope decision.
- **Single isolate.** The bridge only observes the isolate it was
  initialized in; it does not aggregate across isolates.
- **VM Service extensions cannot be unregistered.** After `dispose()`,
  `ext.all_observer.*` calls keep responding, but reflect an idle bridge
  (`streamingEnabled: false`) — `getSnapshot`/`getEvents`/`getStatus` still
  read live data from `ObserverProtocol`, which this package never owns.
- **Git dependency on `all_observer`'s `protocol-v1` branch.** This package
  currently depends on `all_observer` via `git: {url, ref: protocol-v1}`,
  tracking the branch where the Observer Protocol is being developed and
  published ahead of a tagged release. Publishing `all_observer_devtools` to
  pub.dev requires switching this to a version constraint once
  `protocol-v1` merges and ships as a numbered `all_observer` release.

## Requirements

- Flutter `>=1.17.0`, Dart SDK `^3.9.2` (matching `all_observer`'s own
  minimums).
- `all_observer`'s Observer Protocol, version `1` (`observerProtocolVersion`
  in `package:all_observer`). This package targets protocol contract
  version `1` end to end — no core changes were required to build it.
