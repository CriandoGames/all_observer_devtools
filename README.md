# all_observer_devtools

Opt-in Flutter DevTools integration for
[`all_observer`](https://github.com/CriandoGames/all_observer): a read-only
diagnostics bridge from the Observer Protocol to the Dart VM Service.

> **Status: runtime bridge + unpublished extension panel.** The package root
> ships the piece an app depends on and initializes — the Observer Protocol
> consumer, the `ext.all_observer.*` VM Service extensions, and the batched
> event transport. `extension/` now also contains the Flutter Web DevTools
> panel (Overview / Nodes / Timeline / Dependencies / Scopes / Warnings) that
> reads this data, as a companion extension source package. It has not yet
> been built and copied into `extension/devtools/build`, has no example app
> wired up, and its one VM-Service-specific file
> (`vm_service_adapter.dart`) has not been verified against a real DevTools
> host — see [The extension panel](#the-extension-panel) below.

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

## The extension panel

The visual DevTools panel lives under `extension/`, laid out to match the
official `devtools_extensions` "companion extension" recommendation for
packages that are also imported at runtime by consuming apps:

```
extension/
  devtools/
    config.yaml        # extension metadata devtools_extensions reads
    build/              # build output goes here (currently a .gitkeep only)
  devtools_source/      # the actual Flutter Web app, its own pubspec.yaml
    lib/
      main.dart
      src/
        app/            # DevToolsExtension shell, tab scaffold, connection banner
        connection/     # ProtocolClient, ConnectionController, VmServiceAdapter
        models/         # wire-format mirrors of the bridge's JSON codec
        store/          # DevToolsStore — snapshot+event reconciliation
        screens/         # overview, nodes, timeline, dependencies, scopes, warnings
    test/
```

`devtools_source` is a separate, `publish_to: none` Dart package — it is
never added to an app's `dependencies`. It only exists so
`dart run devtools_extensions build_and_copy` can compile it and copy the
result into `extension/devtools/build`, which is what a real DevTools
instance loads.

**The panel's own UI reactivity is `all_observer` itself** — `DevToolsStore`
and `ConnectionController` hold `Observable`/reactive-collection fields
(no `ChangeNotifier`), and every screen wraps its `build()` in an
`Observer`. `extension/devtools_source/pubspec.yaml` depends on
`all_observer` (same `git: {ref: protocol-v1}` as the runtime bridge) for
this alone — it is never used to decode the Observer Protocol wire format,
which stays hand-written in `lib/src/models`. This means the panel that
observes other apps' `all_observer` usage is itself a live example of
`all_observer` usage.

**Building it** (from `extension/devtools_source`):

```
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../devtools/build
```

**Testing it locally**, once built, DevTools' simulated environment can load
it without a real connected app:

```
flutter run -d chrome --dart-define=use_simulated_environment=true
```

against `extension/devtools_source`. Testing against a real running app
requires that app to depend on this package's root (the runtime bridge),
call `AllObserverDevTools.initialize()`, and be opened from DevTools'
Extensions tab.

**State/reconciliation model** (`DevToolsStore`): the snapshot from
`getSnapshot` is always authoritative; events are ordered and deduplicated
by `sequenceNumber`, never by timestamp; a sequence gap or a
foreign-session event triggers `needsResync` and an automatic re-fetch of a
fresh snapshot (bounded retries); nothing is guessed or invented when data
is missing — unknown node references and disposal failures surface as
explicit diagnostics instead.

**Known gaps in this pass:**

- Not yet built/copied into `extension/devtools/build` — no `.gitkeep`
  replacement yet.
- `VmServiceAdapter` (`extension/devtools_source/lib/src/connection/vm_service_adapter.dart`)
  is the only file touching `serviceManager`/`package:vm_service` directly;
  its exact API surface (`serviceManager.isolateManager.selectedIsolate`,
  `service.streamListen`, `service.callServiceExtension`) was written from
  established knowledge of `devtools_app_shared`/`vm_service`, not verified
  against the locally installed package versions — flagged in a doc comment
  in that file for review against `flutter analyze` output.
- No CI wiring, no `dart run devtools_extensions validate` run yet (neither
  is runnable in the environment this was built in).
- Dependencies screen is tabular only — no graph rendering (allowed by the
  spec as an MVP fallback).
- Read-only by design: no way to trigger app actions from the panel.

## Example app

`example/` is a standalone Flutter app (depends on `all_observer` and on
this package's root via `path: ../`) built specifically to exercise the
extension panel end to end: an `Observable`/`Computed` counter, a reactive
task list, a debounce-worker search, an `ObservableFuture` profile load
(with a "force error" toggle), and a "dynamic counters" section that
creates and disposes nodes/scopes at runtime — the one part of the demo
that isn't just steady-state, so the Nodes screen's "Disposed" filter and
the Scopes screen's disposal diagnostics have something real to show.
`AllObserverDevTools.initialize()` runs on startup. See
`example/README.md` for first-time setup (it needs `flutter create` run
once locally to add platform folders, which aren't checked in) and how to
watch it from DevTools.

## Limitations

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
