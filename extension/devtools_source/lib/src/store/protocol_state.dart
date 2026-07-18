import '../models/dependency_model.dart';
import '../models/node_model.dart';
import '../models/scope_model.dart';

/// Mutable current-state tables the store folds snapshot + events into.
/// Deliberately plain `Map`s keyed by stable integer identity — never by
/// label — so every lookup/update is O(1) even with thousands of nodes,
/// per the implementation spec's performance section (no `firstWhere` scans
/// on every event).
final class ProtocolState {
  final Map<int, NodeModel> nodes = <int, NodeModel>{};
  final Map<int, DependencyModel> dependencies = <int, DependencyModel>{};
  final Map<int, ScopeModel> scopes = <int, ScopeModel>{};
}
