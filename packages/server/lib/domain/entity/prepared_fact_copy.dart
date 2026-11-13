/// A fact copy whose blobs are already duplicated, ready to be inserted into
/// the destination beacon (plan §5.2). [attachmentsJson] already points at
/// the new blobs; [newImageIds] lists them for compensation and hash tasks.
class PreparedFactCopy {
  const PreparedFactCopy({
    required this.originFactCardId,
    required this.originRevisionSeq,
    required this.originBeaconKind,
    required this.factText,
    required this.attachmentsJson,
    required this.newImageIds,
  });

  final String originFactCardId;
  final int originRevisionSeq;

  /// 0 Request, 1 Post.
  final int originBeaconKind;

  final String factText;
  final String attachmentsJson;
  final List<String> newImageIds;
}
