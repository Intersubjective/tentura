import 'build_id.dart';

/// Compile-time build metadata injected via `--dart-define` in CI web builds.
abstract final class AppBuildInfo {
  static const gitSha = String.fromEnvironment('BUILD_GIT_SHA');
  static const buildDate = String.fromEnvironment('BUILD_DATE');

  /// Settings app-bar label: semver, optional shortened git SHA, optional date.
  static String formatVisibleVersionLabel(
    String semver, {
    String gitShaOverride = gitSha,
    String buildDateOverride = buildDate,
  }) {
    final parts = [semver];
    final sha = sanitizeBuildId(gitShaOverride);
    if (sha.isNotEmpty) parts.add(sha);
    if (buildDateOverride.isNotEmpty) parts.add(buildDateOverride);
    return parts.join(' · ');
  }
}
