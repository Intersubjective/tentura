/// What a stored fact says about where it was copied from.
class FactOriginRef {
  const FactOriginRef({
    required this.status,
    required this.visibility,
    this.originFactCardId,
    this.originRevisionSeq,
  });

  final int status;
  final int visibility;
  final String? originFactCardId;
  final int? originRevisionSeq;
}

/// One head-revision attachment of a [FactCopySource]: the stored JSON entry,
/// whether its `public.image` row exists (plan §5.2 step 5, R2) and, for a
/// file entry, the storage key of its object.
class FactCopySourceAttachment {
  const FactCopySourceAttachment({
    required this.fields,
    required this.imageExists,
    this.fileKey,
  });

  final Map<String, Object?> fields;

  /// False for a non-image entry, a malformed `imageId`, or a deleted row.
  final bool imageExists;

  /// Storage key of a file entry's object: the copy's own `fileKey`, or the
  /// pinned message attachment's `file_url`. Null for an image entry or a
  /// file whose object is unknown.
  final String? fileKey;
}

/// A file attachment of a copied fact's head revision, as found by its
/// attachment id: the fact it belongs to and the object holding its bytes.
typedef CopiedFactFile = ({
  String beaconId,
  int status,
  int visibility,
  String fileKey,
  String mime,
  String fileName,
});

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
