/// The extension-side connection state machine (implementation spec section
/// 16). Every state must be presented to the user with an explanation —
/// never a blank screen.
enum DevToolsConnectionState {
  /// No VM Service connection, or no isolate selected yet.
  disconnected,

  /// A VM Service connection exists; the extension has started its
  /// handshake but has not yet requested protocol info.
  connecting,

  /// Awaiting `ext.all_observer.getProtocolInfo`.
  loadingProtocolInfo,

  /// Protocol info is compatible; awaiting `ext.all_observer.getSnapshot`.
  loadingSnapshot,

  /// Snapshot applied; replaying events buffered during the snapshot
  /// request and enabling live streaming.
  synchronizing,

  /// Steady state: snapshot applied, live events flowing, no gap.
  connected,

  /// A gap or foreign-session event was detected; re-fetching a snapshot.
  reconnecting,

  /// `ProtocolInfoModel.isCompatibleWith` returned false — the extension
  /// must not interpret any further data from this bridge.
  incompatible,

  /// The VM Service is connected, but no `ext.all_observer.*` extension is
  /// registered on the selected isolate (the app never called
  /// `AllObserverDevTools.initialize()`, or it's a release build).
  unavailable,

  /// An unexpected failure occurred (serialization, RPC failure, etc).
  /// [ConnectionController.errorMessage] carries a description.
  error,
}
