/// Readable Post content attached to a pending digest receipt.
class DigestPostContent {
  const DigestPostContent({
    required this.excerpt,
    required this.senderName,
    required this.senderNote,
  });

  final String excerpt;
  final String senderName;
  final String senderNote;
}
