import 'protocol_event_model.dart';

enum WarningSeverityModel { info, warning, error, unknown }

WarningSeverityModel _parseSeverity(String raw) => switch (raw) {
  'info' => WarningSeverityModel.info,
  'warning' => WarningSeverityModel.warning,
  'error' => WarningSeverityModel.error,
  // A future protocol version could add a severity this extension does not
  // know yet — degrade to "unknown" rather than crash or silently drop it.
  _ => WarningSeverityModel.unknown,
};

/// Display-oriented wrapper around a [WarningRaisedEventModel] for the
/// Warnings screen. Adds nothing the protocol didn't already report —
/// just a typed severity instead of a raw string.
final class WarningModel {
  WarningModel(WarningRaisedEventModel event)
    : sequenceNumber = event.sequenceNumber,
      timestampMicros = event.timestampMicros,
      warningCode = event.warningCode,
      message = event.message,
      suggestion = event.suggestion,
      objectId = event.objectId,
      severity = _parseSeverity(event.severity);

  final int sequenceNumber;
  final int timestampMicros;
  final String warningCode;
  final String message;
  final String? suggestion;
  final int? objectId;
  final WarningSeverityModel severity;
}
