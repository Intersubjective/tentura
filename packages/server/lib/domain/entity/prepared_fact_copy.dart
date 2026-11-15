import 'package:tentura_server/utils/id.dart';

/// A fact copy whose blobs are already duplicated, ready to be inserted into
/// the destination beacon (plan §5.2). [attachmentsJson] already points at
/// the new blobs; [newImageIds] lists the new images for compensation and
/// hash tasks, [newFileKeys] the storage keys of the new file objects.
/// [factCardId] is the id the copy is inserted under; an insert that answers
/// another id lost the race to an existing live copy.
class PreparedFactCopy {
  PreparedFactCopy({
    required this.originFactCardId,
    required this.originRevisionSeq,
    required this.originBeaconKind,
    required this.factText,
    required this.attachmentsJson,
    required this.newImageIds,
    this.newFileKeys = const [],
    String? factCardId,
  }) : factCardId = factCardId ?? generateId('F');

  final String factCardId;

  final String originFactCardId;
  final int originRevisionSeq;

  /// 0 Request, 1 Post.
  final int originBeaconKind;

  final String factText;
  final String attachmentsJson;
  final List<String> newImageIds;
  final List<String> newFileKeys;
}
