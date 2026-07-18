/// Shared vocabulary for "is the bridge itself alive" — distinct from, and
/// much smaller than, the extension UI's own connection state machine
/// (section 16 of the implementation spec), which also tracks snapshot
/// loading, reconciliation, and incompatibility and lives in the separate
/// Flutter Web extension package built in a later phase.
///
/// This enum only answers: has [AllObserverDevTools.initialize] run, and is
/// it currently forwarding events. It is exposed so tests and any future
/// extension-side client can name these states consistently instead of
/// inventing their own strings.
enum BridgeLifecycleState {
  /// [AllObserverDevTools.initialize] has not been called, was called with
  /// `enabled: false`, or was called in release mode (a no-op either way).
  uninitialized,

  /// Initialized: the protocol consumer is registered and service
  /// extensions are available. Streaming may still be off — see
  /// `ext.all_observer.setStreaming`.
  initialized,

  /// [AllObserverDevTools.dispose] has run: consumer unregistered, timers
  /// cancelled, buffers cleared.
  disposed,
}
