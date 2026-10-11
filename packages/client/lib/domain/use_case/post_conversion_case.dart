import 'package:injectable/injectable.dart';

import 'package:tentura/domain/port/post_conversion_port.dart';

export 'package:tentura/domain/port/post_conversion_port.dart'
    show PostRootContent;

/// Owns the rules of turning a Post into a Request: which values reach
/// `beaconConvertToRequest`. The form prefill lives in `MessagePrefillCase`.
@singleton
class PostConversionCase {
  PostConversionCase(this._port);

  final PostConversionPort _port;

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
