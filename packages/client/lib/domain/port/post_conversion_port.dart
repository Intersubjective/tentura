import 'package:tentura/domain/entity/image_entity.dart';

/// What the Request form is prefilled from: the Post's root message.
final class PostRootContent {
  const PostRootContent({required this.body, this.firstImage});

  final String body;

  /// First image attachment of the root message, with its bytes loaded so it
  /// can be uploaded again as the Request's cover.
  final ImageEntity? firstImage;
}

/// Reading a Post's root message and converting the Post to a Request.
abstract interface class PostConversionPort {
  Future<PostRootContent> fetchRootContent(String beaconId);

  /// Writes the Request content and flips the Post to a Request in one call.
  Future<void> convertToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String> helperIds = const [],
  });
}
