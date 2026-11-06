import 'package:meta/meta.dart';

import 'forward_edge_entity.dart';
import 'help_path_node.dart';

/// Where the recipient of a forward stands with their help offer on the
/// beacon. Enum names are the public wire values.
enum ForwardRecipientOfferStatus {
  none,
  offered,
  accepted,
  withdrawn,
  declinedByAuthor,
}

/// One live forward edge of a beacon's tree, read for one viewer.
@immutable
class ForwardTreeEdge {
  const ForwardTreeEdge({
    required this.edge,
    required this.sender,
    required this.recipient,
    required this.recipientDeclined,
    required this.recipientOffer,
  });

  final ForwardEdgeEntity edge;

  /// Named, or anonymous when a block hides that person from the viewer.
  final HelpPathNode sender;
  final HelpPathNode recipient;

  /// The recipient answered «can't make it»: rejected the forward in the
  /// inbox, or declined the author invitation this edge delivered.
  final bool recipientDeclined;

  final ForwardRecipientOfferStatus recipientOffer;
}
