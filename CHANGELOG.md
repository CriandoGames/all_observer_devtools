## 0.1.0

Initial runtime bridge release (Phase 1 of the implementation plan — the
Flutter Web DevTools extension panel itself ships in a later release).

- `AllObserverDevTools.initialize()` / `.dispose()`: explicit, idempotent,
  no-op in release builds and when `enabled: false`.
- Consumes `all_observer`'s Observer Protocol via a single
  `ObserverProtocolInspector` registered into `ObserverConfig.inspectors` —
  no changes to the core package were needed.
- Registers `ext.all_observer.getProtocolInfo`, `.getSnapshot`,
  `.getEvents`, `.setStreaming`, `.clearBuffer`, and `.getStatus` VM Service
  extensions, each returning a structured `{success, protocolVersion,
  sessionId, data}` / `{success: false, error: {code, message}}` envelope.
  Duplicate registration on hot restart is caught and ignored.
- Live events are batched (`batchInterval` / `maxBatchSize` /
  `maxPayloadBytes`, all configurable) and posted on the
  `all_observer:events` VM Service extension stream. Batching never mixes
  two sessions and preserves `sequenceNumber` order. Streaming is off by
  default — `add()` is a single boolean check with no allocation until a
  client calls `setStreaming(enabled: true)`.
- Deterministic JSON codec for every protocol event type and for
  `ObserverProtocolSnapshot`, covered by golden fixtures under
  `test/fixtures/protocol_v1/`.
- No Flutter DevTools, `devtools_extensions`, `vm_service`, or Flutter Web
  dependency in this package — see the README's Limitations section.
- Depends on `all_observer` via `git: {url, ref: protocol-v1}`, tracking
  https://github.com/CriandoGames/all_observer/tree/protocol-v1 — including
  `ObserverProtocolConfig.redactValue`, forwarded through
  `AllObserverDevToolsConfig.redactValue`.
