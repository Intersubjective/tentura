import 'package:logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart' as url;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';

@Singleton(
  as: PlatformRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class PlatformRepository implements PlatformRepositoryPort {
  const PlatformRepository({
    required Logger log,
  }) : _log = log;

  final Logger _log;

  @override
  Future<String> getStringFromClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';

  @override
  Future<String> getAppVersion() =>
      PackageInfo.fromPlatform().then((info) => info.version);

  @override
  Future<void> launchUrl(String uri) => url.launchUrl(Uri.parse(uri));

  @override
  Future<void> launchUri(Uri uri) async {
    try {
      await url.launchUrl(uri);
    } catch (e) {
      _log.severe(e);
      throw const UnknownPlatformException();
    }
  }
}
