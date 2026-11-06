import 'package:meta/meta.dart';

/// One named participant on the canonical help path, or a run hidden by a block.
@immutable
class HelpPathNode {
  const HelpPathNode.named({
    required this.userId,
    required this.displayName,
  }) : anonymousCount = 0;

  const HelpPathNode.anonymous(this.anonymousCount)
    : assert(
        anonymousCount > 0,
        'Anonymous groups must contain at least one person',
      ),
      userId = null,
      displayName = null;

  final String? userId;
  final String? displayName;
  final int anonymousCount;

  bool get isAnonymous => anonymousCount > 0;
}

/// True when the ordered path includes at least one forwarder between author and helper.
bool helpPathShowsClosureRow(List<HelpPathNode> path) => path.length > 2;
