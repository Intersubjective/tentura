import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  test('classifies network errors', () {
    final details = describeScreenLoadError(
      error: const ConnectionUplinkException(),
      l10n: l10n,
    );
    expect(details.kind, ScreenLoadErrorKind.network);
    expect(details.title, l10n.screenLoadErrorNetworkTitle);
    expect(details.supportRef, startsWith('E'));
  });

  test('classifies session errors', () {
    final details = describeScreenLoadError(
      error: const AuthSessionLostException(),
      l10n: l10n,
    );
    expect(details.kind, ScreenLoadErrorKind.session);
    expect(details.message, contains('session'));
  });

  test('surfaces server message as detail', () {
    final details = describeScreenLoadError(
      error: const RemoteApiException('field "foo" not found'),
      l10n: l10n,
    );
    expect(details.kind, ScreenLoadErrorKind.server);
    expect(details.detail, 'field "foo" not found');
  });

  test('classifies permission-like server messages', () {
    final details = describeScreenLoadError(
      error: const RemoteApiException('permission denied for table beacon'),
      l10n: l10n,
    );
    expect(details.kind, ScreenLoadErrorKind.permissions);
  });

  test('a read still refused after its retries is a server error with '
      'readable text', () {
    final details = describeScreenLoadError(
      error: const RemoteApiRetryLaterException(Duration(seconds: 2)),
      l10n: l10n,
    );
    expect(details.kind, ScreenLoadErrorKind.server);
    expect(details.message, isNot(contains('RETRY_LATER')));
    expect(details.message, contains('busy'));
  });

  test('retry-later text is localized in Russian', () {
    const error = RemoteApiRetryLaterException(Duration(seconds: 2));
    expect(error.toRu, isNot(contains('RETRY_LATER')));
    expect(error.toRu, contains('Сервер занят'));
  });
}
