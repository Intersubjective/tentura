/// Clipboard / URL / app version (implemented by `PlatformRepository` in the
/// data layer).
abstract class PlatformRepositoryPort {
  Future<String> getStringFromClipboard();

  Future<String> getAppVersion();

  /// Launches an app-generated [uri] (maps `geo:`, invite `mailto:`, a
  /// server-issued sign-in link). Throws `UnknownPlatformException` when the
  /// platform launcher throws; the launcher's `false` ("could not launch")
  /// result is not reported.
  Future<void> launchUri(Uri uri);

  /// Launches a user-authored/pasted link (e.g. tapped in chat or a
  /// description). Unlike [launchUri], which trusts app-generated URIs
  /// (maps `geo:`, invite `mailto:`), this enforces an http/https scheme
  /// allowlist and forces an external launch mode. A link with any other
  /// scheme is refused: logged and not launched, and the call returns
  /// normally. A launcher failure throws `UnknownPlatformException`, as
  /// [launchUri] does.
  Future<void> launchUserLink(Uri uri);
}
