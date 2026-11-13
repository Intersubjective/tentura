/// One head-revision attachment of a [FactCopySource]: the stored JSON entry
/// and whether its `public.image` row exists (plan §5.2 step 5, R2).
class FactCopySourceAttachment {
  const FactCopySourceAttachment({
    required this.fields,
    required this.imageExists,
  });

  final Map<String, Object?> fields;

  /// False for a non-image entry, a malformed `imageId`, or a deleted row.
  final bool imageExists;
}

/// A fact as loaded for copying (plan §5.2 step 2): its episode, status,
/// visibility and head revision.
class FactCopySource {
  const FactCopySource({
    required this.factCardId,
    required this.beaconId,
    required this.beaconKind,
    required this.status,
    required this.visibility,
    required this.headRevisionSeq,
    required this.headText,
    required this.attachments,
  });

  final String factCardId;
  final String beaconId;

  /// 0 Request, 1 Post.
  final int beaconKind;

  final int status;
  final int visibility;
  final int headRevisionSeq;
  final String headText;
  final List<FactCopySourceAttachment> attachments;
}
