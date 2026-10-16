import 'dart:io' show Platform;

bool get isDesktopPlatform =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

String get platformName =>
    Platform.isLinux
        ? 'linux'
        : Platform.isWindows
            ? 'windows'
            : Platform.isMacOS
                ? 'macos'
                : 'android';

/// Native builds are never an installed web app.
bool get isInstalledWebApp => false;
