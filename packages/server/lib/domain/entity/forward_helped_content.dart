import 'help_path_node.dart';

/// The recipient's frozen, block-masked help path, shared by push and digest.
class ForwardHelpedContent {
  const ForwardHelpedContent({
    required this.beaconTitle,
    required this.helperId,
    required this.path,
    required this.done,
  });

  final String beaconTitle;
  final String? helperId;
  final List<HelpPathNode> path;
  final bool done;

  static ForwardHelpedContent? fromPayload(Object? payload) {
    if (payload case {
      'eventType': 'forwardHelped',
      'path': final List<Object?> nodes,
    }) {
      return ForwardHelpedContent(
        beaconTitle: switch (payload) {
          {'beaconTitle': final String title} => title,
          _ => '',
        },
        helperId: switch (payload) {
          {'helperId': final String id} => id,
          _ => null,
        },
        path: List.unmodifiable([
          for (final node in nodes)
            switch (node) {
              {'userId': final String id, 'displayName': final String name} =>
                HelpPathNode.named(userId: id, displayName: name),
              {'anonymousCount': final int count} when count > 0 =>
                HelpPathNode.anonymous(count),
              _ => throw const FormatException(
                'Invalid forward help path node',
              ),
            },
        ]),
        done: switch (payload) {
          {'done': true} => true,
          _ => false,
        },
      );
    }
    return null;
  }

  Map<String, Object?> toPayload() => {
    'eventType': 'forwardHelped',
    'beaconTitle': beaconTitle,
    'helperId': helperId,
    'done': done,
    'path': [
      for (final node in path)
        {
          'userId': node.userId,
          'displayName': node.displayName,
          'anonymousCount': node.anonymousCount,
        },
    ],
  };
}
