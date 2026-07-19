/// Response of `ext.all_observer.getProtocolInfo` — the version negotiation
/// surface described in the implementation spec's compatibility section.
final class ProtocolInfoModel {
  const ProtocolInfoModel({
    required this.protocolVersion,
    required this.packageVersion,
    required this.minimumSupportedProtocolVersion,
    required this.maximumSupportedProtocolVersion,
    required this.capabilities,
  });

  factory ProtocolInfoModel.fromJson(Map<String, Object?> json) =>
      ProtocolInfoModel(
        protocolVersion: json['protocolVersion'] as int,
        packageVersion: json['packageVersion'] as String,
        minimumSupportedProtocolVersion:
            json['minimumSupportedProtocolVersion'] as int,
        maximumSupportedProtocolVersion:
            json['maximumSupportedProtocolVersion'] as int,
        capabilities: (json['capabilities'] as List).cast<String>(),
      );

  final int protocolVersion;
  final String packageVersion;
  final int minimumSupportedProtocolVersion;
  final int maximumSupportedProtocolVersion;
  final List<String> capabilities;

  /// This extension only ever speaks protocol version 1 — see
  /// `_extensionSupportedProtocolVersion` in `protocol_client.dart`. `false`
  /// means the connection state machine must stop interpreting data from
  /// this bridge rather than guess at a newer/older shape.
  bool isCompatibleWith(int supportedVersion) =>
      supportedVersion >= minimumSupportedProtocolVersion &&
      supportedVersion <= maximumSupportedProtocolVersion;
}
