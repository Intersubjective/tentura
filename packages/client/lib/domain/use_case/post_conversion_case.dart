import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/post_conversion_port.dart';

export 'package:tentura/domain/port/post_conversion_port.dart'
    show PostRootContent;

/// Request form content derived from a Post's root message.
typedef PostConversionPrefill = ({
  String title,
  String description,
  ImageEntity? coverSuggestion,
});

/// Owns the rules of turning a Post into a Request: how the root message fills
/// the form and which values reach `beaconConvertToRequest`.
@singleton
class PostConversionCase {
  PostConversionCase(this._port);

  final PostConversionPort _port;

  /// First line → title (cut to the title limit), the rest → description,
  /// first image → cover suggestion.
  Future<PostConversionPrefill> prefill(String beaconId) async {
    final root = await _port.fetchRootContent(beaconId);
    final body = root.body.trim();
    final newline = body.indexOf('\n');
    final firstLine = (newline < 0 ? body : body.substring(0, newline)).trim();
    final rest = newline < 0 ? '' : body.substring(newline + 1).trim();
    return (
      title: firstLine.length > kBeaconTitleMaxLength
          ? firstLine.substring(0, kBeaconTitleMaxLength)
          : firstLine,
      description: rest,
      coverSuggestion: root.firstImage,
    );
  }

  Future<void> convert({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String> helperIds = const [],
  }) => _port.convertToRequest(
    beaconId: beaconId,
    title: title,
    description: description,
    needs: needs,
    primaryNeedSlug: primaryNeedSlug,
    startAt: startAt,
    endAt: endAt,
    isDiscoverable: isDiscoverable,
    helperIds: helperIds,
  );
}
