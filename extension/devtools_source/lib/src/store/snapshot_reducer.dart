import '../models/snapshot_model.dart';
import 'protocol_state.dart';

/// Pure function: builds a fresh [ProtocolState] entirely from
/// [snapshot] — the authoritative base a client reconciles events on top
/// of (implementation spec, section 12). Never merges with any prior
/// state; the caller (`DevToolsStore`) decides whether applying a new
/// snapshot means "first load" or "resync", but either way the resulting
/// table is always a clean rebuild from the snapshot's contents.
ProtocolState buildStateFromSnapshot(ProtocolSnapshotModel snapshot) {
  final ProtocolState state = ProtocolState();
  for (final node in snapshot.nodes) {
    state.nodes[node.objectId] = node;
  }
  for (final dependency in snapshot.dependencies) {
    if (dependency.dependencyIds.isNotEmpty) {
      state.dependencies[dependency.trackerId] = dependency;
    }
  }
  for (final scope in snapshot.scopes) {
    state.scopes[scope.scopeId] = scope;
  }
  return state;
}
