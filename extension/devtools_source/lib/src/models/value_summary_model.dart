/// Mirrors the `ObserverValueSummary` JSON shape produced by
/// `encodeEvent`/`encodeSnapshot` in the runtime bridge
/// (`all_observer_devtools/lib/src/serialization`). Never holds a raw
/// application value — only what the bridge already redacted/summarized.
final class ValueSummaryModel {
  const ValueSummaryModel({
    required this.type,
    this.display,
    this.isRedacted = false,
    this.isTruncated = false,
  });

  factory ValueSummaryModel.fromJson(Map<String, Object?> json) =>
      ValueSummaryModel(
        type: json['type'] as String,
        display: json['display'] as String?,
        isRedacted: json['isRedacted'] as bool? ?? false,
        isTruncated: json['isTruncated'] as bool? ?? false,
      );

  final String type;
  final String? display;
  final bool isRedacted;
  final bool isTruncated;

  /// Best-effort single-line text for a table cell: the display text when
  /// present, otherwise a placeholder explaining *why* there is none. Never
  /// falls back to guessing or calling `toString()` on anything — there is
  /// nothing but this summary to work with.
  String get shortDisplay {
    if (isRedacted) {
      return '<redacted>';
    }
    if (display == null) {
      return '<$type>';
    }
    return isTruncated ? '$display…' : display!;
  }
}
