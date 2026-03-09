import 'dart:async';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:share_handler/share_handler.dart'
    if (dart.library.js_interop) 'share_handler_dummy.dart';
import 'package:tentura/app/platform/platform_info.dart';

@singleton
class ShareHandlerService {
  ShareHandlerService(this._logger) {
    if (!kIsWeb && !isDesktopPlatform) {
      _subscription = ShareHandler.instance.sharedMediaStream.listen(_handler);
      unawaited(ShareHandler.instance.getInitialSharedMedia().then(_handler));
    }
  }

  final Logger _logger;

  StreamSubscription<SharedMedia>? _subscription;

  @disposeMethod
  Future<void> dispose() =>
      _subscription?.cancel() ?? Future.value();

  void _handler(SharedMedia? e) {
    if (e == null) return;

    _logger.info('String: ${e.content}');

    if (e.attachments != null) {
      for (final e in e.attachments!) {
        _logger.info('Attached: ${e?.path}');
      }
    }
  }
}
