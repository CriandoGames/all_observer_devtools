import 'protocol_event_model.dart';

/// Current active dependency set for one tracker. Mirrors
/// `ObserverDependencySnapshot`/`DependenciesChangedEvent.currentDependencyIds`
/// — always the *complete* set, never a delta, so the store can simply
/// replace an entry wholesale instead of merging.
final class DependencyModel {
  const DependencyModel({required this.trackerId, required this.dependencyIds});

  factory DependencyModel.fromSnapshotJson(Map<String, Object?> json) {
    final Object? trackerId = json['trackerId'];
    final Object? dependencyIds = json['dependencyIds'];
    if (trackerId is! int || dependencyIds is! List) {
      throw ProtocolDecodeError('Malformed dependency snapshot entry: $json');
    }
    return DependencyModel(
      trackerId: trackerId,
      dependencyIds: dependencyIds.cast<int>().toSet(),
    );
  }

  final int trackerId;
  final Set<int> dependencyIds;
}
