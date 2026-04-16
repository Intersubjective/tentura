import 'package:tentura/data/repository/platform_repository.dart' show PlatformRepository;

/// Clipboard / URL / app version (implemented by [PlatformRepository]).
abstract class PlatformRepositoryPort {
  Future<String> getStringFromClipboard();

  Future<String> getAppVersion();

  Future<void> launchUrl(String uri);

  Future<void> launchUri(Uri uri);
}
