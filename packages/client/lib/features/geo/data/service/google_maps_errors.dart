/// Thrown by the Google Maps services when no API key is configured.
///
/// A [StateError] like every other refusal from these services, so callers
/// that only care about "the service refused" keep working; callers that
/// need to tell the missing key apart check the type, not the message.
final class GoogleMapsKeyMissingError extends StateError {
  GoogleMapsKeyMissingError() : super('GOOGLE_MAPS_API_KEY is not configured');
}
