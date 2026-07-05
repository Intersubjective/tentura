import 'package:tentura/data/repository/platform_repository.dart' show PlatformRepository;

/// Clipboard / URL / app version (implemented by [PlatformRepository]).
abstract class PlatformRepositoryPort {
  Future<String> getStringFromClipboard();

  Future<String> getAppVersion();

  Future<void> launchUrl(String uri);

  Future<void> launchUri(Uri uri);

  /// Launches a user-authored/pasted link (e.g. tapped in chat or a
  /// description). Unlike [launchUri], which trusts app-generated URIs
  /// (maps `geo:`, invite `mailto:`), this enforces an http/https scheme
  /// allowlist and forces an external launch mode.
  Future<void> launchUserLink(Uri uri);
}
