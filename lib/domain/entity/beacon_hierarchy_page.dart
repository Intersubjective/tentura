import 'beacon_hierarchy_summary.dart';

/// One page of child summaries for a parent request.
class BeaconHierarchyPage {
  const BeaconHierarchyPage({
    required this.summaries,
    this.nextCursor,
  });

  final List<BeaconHierarchySummary> summaries;
  final String? nextCursor;
}
