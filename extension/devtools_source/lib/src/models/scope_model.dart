import 'protocol_event_model.dart';

final class ScopeResourceModel {
  const ScopeResourceModel({
    required this.resourceId,
    required this.resourceKind,
  });

  factory ScopeResourceModel.fromJson(Map<String, Object?> json) {
    final Object? resourceId = json['resourceId'];
    final Object? resourceKind = json['resourceKind'];
    if (resourceId is! int || resourceKind is! String) {
      throw ProtocolDecodeError('Malformed scope resource entry: $json');
    }
    return ScopeResourceModel(
      resourceId: resourceId,
      resourceKind: resourceKind,
    );
  }

  final int resourceId;
  final String resourceKind;
}

/// Current-state view of one active scope. Mirrors `ObserverScopeSnapshot`.
/// A disposed scope is removed from the store entirely (the protocol does
/// not keep disposed scopes in the registry) — its disposal is instead
/// recorded as a [ScopeDisposedEventModel] row in the timeline/warnings
/// views, per the implementation spec's ban on treating a disposed
/// resource as still "active".
final class ScopeModel {
  const ScopeModel({
    required this.scopeId,
    required this.debugLabel,
    required this.resources,
  });

  factory ScopeModel.fromSnapshotJson(Map<String, Object?> json) {
    final Object? scopeId = json['scopeId'];
    final Object? debugLabel = json['debugLabel'];
    final Object? resources = json['resources'];
    if (scopeId is! int || debugLabel is! String || resources is! List) {
      throw ProtocolDecodeError('Malformed scope snapshot entry: $json');
    }
    return ScopeModel(
      scopeId: scopeId,
      debugLabel: debugLabel,
      resources: resources
          .cast<Map<String, Object?>>()
          .map(ScopeResourceModel.fromJson)
          .toList(),
    );
  }

  final int scopeId;
  final String debugLabel;
  final List<ScopeResourceModel> resources;

  ScopeModel copyWithResourceAdded(ScopeResourceModel resource) => ScopeModel(
    scopeId: scopeId,
    debugLabel: debugLabel,
    resources: <ScopeResourceModel>[...resources, resource],
  );
}
