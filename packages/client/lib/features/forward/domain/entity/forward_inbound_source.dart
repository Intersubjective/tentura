class ForwardInboundSource {
  const ForwardInboundSource({
    required this.edgeId,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    required this.isSuggestedSource,
  });

  final String edgeId;
  final String senderId;
  final String senderName;
  final DateTime createdAt;
  final bool isSuggestedSource;
}
