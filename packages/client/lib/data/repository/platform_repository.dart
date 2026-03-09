import 'package:logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart' as url;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:tentura/domain/exception/generic_exception.dart';

@injectable
class PlatformRepository {
  const PlatformRepository({
    required Logger log,
  }) : _log = log;

  final Logger _log;

  Future<String> getStringFromClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';

  Future<String> getAppVersion() =>
      PackageInfo.fromPlatform().then((info) => info.version);

  Future<void> launchUrl(String uri) => url.launchUrl(Uri.parse(uri));

  Future<void> launchUri(Uri uri) async {
    try {
      await url.launchUrl(uri);
    } catch (e) {
      _log.severe(e);
      throw const UnknownPlatformException();
    }
  }
}
