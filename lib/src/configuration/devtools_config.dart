/// Configuration for [AllObserverDevTools.initialize].
///
/// Every field is a plain, explicit knob — there is no hidden auto-detection.
/// The defaults are conservative: values are summarized (never raw), stack
/// traces are off, and batching favors low overhead over latency.
final class AllObserverDevToolsConfig {
  const AllObserverDevToolsConfig({
    this.enabled = true,
    this.batchInterval = const Duration(milliseconds: 100),
    this.maxBatchSize = 200,
    this.maxPayloadBytes = 1 << 20, // 1 MiB
    this.eventBufferSize = 1000,
    this.includeValueSummaries = true,
    this.includeStackTraces = false,
    this.redactValue,
  }) : assert(maxBatchSize > 0),
       assert(maxPayloadBytes > 0),
       assert(eventBufferSize >= 0);

  /// Master opt-in switch. When `false`, [AllObserverDevTools.initialize]
  /// does nothing: no consumer, no service extensions, no buffer growth.
  /// Distinct from release-mode gating (see [AllObserverDevTools]), which
  /// cannot be overridden by this flag.
  final bool enabled;

  /// How often pending events are flushed as a batch when at least one event
  /// is pending and nothing has forced an earlier flush.
  final Duration batchInterval;

  /// Maximum number of events per batch. Reaching this triggers an immediate
  /// flush without waiting for [batchInterval].
  final int maxBatchSize;

  /// Hard cap in UTF-8 bytes for the complete encoded JSON batch envelope.
  /// A single event that cannot fit is dropped visibly through the transport
  /// drop and oversized-event counters.
  final int maxPayloadBytes;

  /// Forwarded to `ObserverProtocolConfig.eventBufferSize`: the size of the
  /// core's own ring buffer, independent of the DevTools batching buffer.
  final int eventBufferSize;

  /// Forwarded to `ObserverProtocolConfig.captureValues`. When `false`, node
  /// values are represented only by their runtime type — no display string.
  final bool includeValueSummaries;

  /// Forwarded to `ObserverProtocolConfig.captureStackTraces`. Off by
  /// default: capturing a stack trace on every event is not free.
  final bool includeStackTraces;

  /// Forwarded to `ObserverProtocolConfig.redactValue`: an optional
  /// application policy that forces a value summary to be redacted, on top
  /// of the core's own sensitive-string heuristics. A throwing policy fails
  /// closed (the core redacts the value rather than propagating the
  /// exception). `null` (the default) applies no extra policy.
  final bool Function(Object? value)? redactValue;

  @override
  String toString() =>
      'AllObserverDevToolsConfig('
      'enabled: $enabled, '
      'batchInterval: $batchInterval, '
      'maxBatchSize: $maxBatchSize, '
      'maxPayloadBytes: $maxPayloadBytes, '
      'eventBufferSize: $eventBufferSize, '
      'includeValueSummaries: $includeValueSummaries, '
      'includeStackTraces: $includeStackTraces, '
      'redactValue: ${redactValue == null ? 'none' : 'set'})';
}
