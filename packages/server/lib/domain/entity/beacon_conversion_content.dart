/// The Request content a Post's author supplies when converting it. Raw wire
/// values: `BeaconCase.convertToRequest` validates and normalizes them.
final class BeaconConversionContent {
  const BeaconConversionContent({
    required this.title,
    this.description,
    this.needs,
    this.primaryNeedSlug,
    this.startAt,
    this.endAt,
  });

  final String title;

  final String? description;

  /// Comma-separated capability slugs.
  final String? needs;

  final String? primaryNeedSlug;

  final DateTime? startAt;

  final DateTime? endAt;
}
