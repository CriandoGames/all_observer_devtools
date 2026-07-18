import 'package:all_observer/all_observer.dart';

/// The single `ObserverProtocolInspector` this package registers into
/// `ObserverConfig.inspectors`. It does nothing but forward every event to
/// [onEvent] — no filtering, no derived state, no heuristics. Filtering
/// (e.g. "only stream while a DevTools client is connected") belongs in
/// [EventBatcher], which this consumer feeds.
///
/// `ObserverConfig.inspectors` already isolates exceptions thrown by any one
/// inspector (see `dispatchToInspectors`), so [onEvent] does not need its
/// own try/catch to protect the reactive system — but it must not itself
/// assume that guarantee for code *within* [onEvent] that runs after the
/// forward (there is none here, by design: this class stays a thin relay).
final class DevToolsProtocolConsumer extends ObserverProtocolInspector {
  DevToolsProtocolConsumer({required void Function(ObserverProtocolEvent event) onEvent})
    : _onEvent = onEvent;

  final void Function(ObserverProtocolEvent event) _onEvent;

  @override
  void onProtocolEvent(ObserverProtocolEvent event) => _onEvent(event);
}
