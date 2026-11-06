import 'package:meta/meta.dart';

/// One named participant, or a run of participants hidden by a block.
@immutable
class HelpPathNode {
  const HelpPathNode.named({
    required String this.userId,
    required String this.displayName,
  }) : anonymousCount = 0;

  const HelpPathNode.anonymous(int count)
    : assert(count > 0, 'Anonymous groups must contain at least one person'),
      userId = null,
      displayName = null,
      anonymousCount = count;

  final String? userId;
  final String? displayName;
  final int anonymousCount;

  static List<HelpPathNode> collapseAnonymous(Iterable<HelpPathNode> nodes) {
    final result = <HelpPathNode>[];
    for (final node in nodes) {
      if (node.anonymousCount > 0 &&
          result.isNotEmpty &&
          result.last.anonymousCount > 0) {
        final count = result.removeLast().anonymousCount + node.anonymousCount;
        result.add(HelpPathNode.anonymous(count));
      } else {
        result.add(node);
      }
    }
    return result;
  }
}
