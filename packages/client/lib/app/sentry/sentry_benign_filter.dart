import 'package:flutter/foundation.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/beacon_lobby/domain/exception/beacon_lobby_exception.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';

/// Whether [error] is an expected, user-facing failure that should not
/// become a Sentry issue (connectivity loss, session expiry, etc.).
bool isBenignSentryThrowable(Object? error) {
  if (error is BeaconPlanException) return true;
  if (error == null) {
    return false;
  }
  if (error is ConnectionUplinkException ||
      error is RequestTimeoutException ||
      error is RemoteApiRetryLaterException ||
      error is BeaconLobbyUnavailableException ||
      error is AuthSessionLostException ||
      error is AuthenticationNoKeyException ||
      error is SessionAuthRejectedException) {
    return true;
  }
  if (error is GraphQLException) {
    return isBenignSentryThrowable(error.error);
  }
  if (error is GraphQLError) {
    return _isExpectedDomainCode(error.extensions?['code']?.toString()) ||
        isBenignSentryExceptionText(error.message);
  }
  if (error is RemoteApiException) {
    return _isExpectedDomainCode(error.code) ||
        isBenignSentryExceptionText(error.message);
  }
  if (error is UserInputException || error is PollingInputExceptions) {
    return true;
  }
  if (error is AuthSeedIsWrongException ||
      error is InvitationCodeIsWrongException ||
      error is AuthIdIsWrongException ||
      error is AuthIdNotFoundException ||
      error is AuthSeedExistsException) {
    return true;
  }
  return isBenignSentryExceptionText(error.toString());
}

// Closed Request, room access, Questions access and admission backoff.
// Only known business rejections: unfamiliar codes must still report.
bool _isExpectedDomainCode(String? code) =>
    const {'1500', '1102', '1338', '1347', '1704'}.contains(code?.trim());

/// Flutter web: a pointer packet hit-tests a render box before first layout.
///
/// Matches both `RenderBox was not laid out` and the gestures-library
/// assertion `Cannot hit test a render box that has never been laid out`.
bool isBenignUnlaidOutPointerHitTest(FlutterErrorDetails details) {
  final library = details.library?.toLowerCase() ?? '';
  final context = details.context?.toDescription().toLowerCase() ?? '';
  return _isUnlaidOutHitTest(
    exceptionText: details.exceptionAsString(),
    library: library,
    context: context,
  );
}

/// Whether [event] should be dropped in `beforeSend`.
///
/// Includes exception-text matches and the Flutter web hit-test race
/// (`RenderBox was not laid out` / `never been laid out` while handling a
/// pointer packet).
bool isBenignSentryEvent(SentryEvent event, Hint hint) {
  final synthetic = hint.get(TypeCheckHint.syntheticException);
  if (synthetic is FlutterErrorDetails &&
      isBenignUnlaidOutPointerHitTest(synthetic)) {
    return true;
  }
  if (isBenignSentryThrowable(event.throwable) ||
      isBenignSentryThrowable(synthetic)) {
    return true;
  }
  final blobs = _errorBlobs(event, hint);
  if (_isUnlaidOutHitTest(
    exceptionText: blobs.exceptionText,
    library: blobs.library,
    context: blobs.context,
  )) {
    return true;
  }
  if (_isViewFocusTraversalNullCheck(
    exceptionText: blobs.exceptionText,
    context: blobs.context,
  )) {
    return true;
  }

  final message = event.message?.formatted ?? '';
  if (isBenignSentryExceptionText(message)) {
    return true;
  }

  final exceptions = event.exceptions;
  if (exceptions == null) {
    return false;
  }

  for (final ex in exceptions) {
    final type = ex.type ?? '';
    if (type.contains('ConnectionUplinkException') ||
        type.contains('RequestTimeoutException') ||
        type.contains('SocketException') ||
        type.contains('AuthSessionLostException') ||
        type.contains('AuthenticationNoKeyException')) {
      return true;
    }
    final value = ex.value ?? '';
    if (isBenignSentryExceptionText(value)) {
      return true;
    }
    if (ex.type == 'AbortError' &&
        value.toLowerCase().contains('serviceworker')) {
      return true;
    }
  }
  return false;
}

/// Exception text, Flutter error library and context gathered from the
/// synthetic-exception hint, the `flutter_error_details` event context and the
/// serialized exceptions.
({String exceptionText, String library, String context}) _errorBlobs(
  SentryEvent event,
  Hint hint,
) {
  final exceptionTexts = <String>[];
  final libraries = <String>[];
  final contexts = <String>[];

  final synthetic = hint.get(TypeCheckHint.syntheticException);
  if (synthetic is FlutterErrorDetails) {
    exceptionTexts.add(synthetic.exception.toString());
    final library = synthetic.library;
    if (library != null) {
      libraries.add(library);
    }
    final context = synthetic.context?.toDescription();
    if (context != null) {
      contexts.add(context);
    }
  }

  final details = event.contexts['flutter_error_details'];
  if (details is Map) {
    final library = details['library'];
    final context = details['context'];
    if (library is String) {
      libraries.add(library);
    }
    if (context is String) {
      contexts.add(context);
    }
  }

  for (final ex in event.exceptions ?? const <SentryException>[]) {
    if (ex.value != null) {
      exceptionTexts.add(ex.value!);
    }
  }

  return (
    exceptionText: exceptionTexts.join('\n'),
    library: libraries.join('\n'),
    context: contexts.join('\n'),
  );
}

/// Flutter web: `WidgetsBindingObserver.didChangeViewFocus` runs focus
/// traversal (`FocusTraversalPolicy._findInitialFocus`, via
/// `FocusNode.rect`) while the semantics / render tree is mid-update and
/// throws `Null check operator used on a null value`. Sentry issue
/// TENTURA-CLIENT-37 (3 events / 2 users, `accessible_navigation=true`,
/// `BeaconViewRoute`); the stack has no first-party frames. Same
/// didChangeViewFocus-before-layout race as
/// https://github.com/flutter/flutter/issues/191508 — drop until a Flutter
/// upgrade carries the fix.
///
/// Requires both the null-check text and the view-focus dispatch context so
/// null checks raised anywhere else still report.
bool _isViewFocusTraversalNullCheck({
  required String exceptionText,
  required String context,
}) =>
    exceptionText.contains('Null check operator used on a null value') &&
    context.contains('WidgetsBindingObserver.didChangeViewFocus');

/// Flutter web: a pointer packet hit-tests a Listener / barrier before the
/// first layout. Same class as TENTURA-CLIENT-2J / -12 / -28.
///
/// Requires both an unlaid-out hit-test message and gestures/pointer-packet
/// context so genuine layout failures (`during layout`, rendering library)
/// still report.
bool _isUnlaidOutHitTest({
  required String exceptionText,
  required String library,
  required String context,
}) {
  final exceptionBlob = exceptionText.toLowerCase();
  if (!exceptionBlob.contains('was not laid out') &&
      !exceptionBlob.contains('never been laid out')) {
    return false;
  }
  final metaBlob = '$library\n$context'.toLowerCase();
  return metaBlob.contains('gestures') ||
      metaBlob.contains('pointer data packet');
}

/// Expected-error rules (TENTURA-CLIENT-38 / -35 / -33 / -3C): these are shown
/// to the user (snackbar / screen-load panel) and must not become issues.
///
/// * `No Internet connection` — offline, [ConnectionUplinkException] text.
/// * `Description is required` — GraphQL validation (business) error.
/// * `Id not found: [<id>]` — expected not-found for a missing / deleted id.
/// * `[<label>] load failed ... kind=network` — screen-load diagnostic for an
///   offline / timeout failure (see `logScreenLoadError`). A cancelled request
///   (`kind=cancelled`) or an unavailable server (`kind=unavailable`, HTTP 5xx
///   / 408 / 429) is dropped the same way while that attempt will be retried
///   (`retrying=1`). Once the load has failed for good, those two kinds are
///   reported. `kind=server` (a GraphQL error) and `kind=unknown` (a parse or
///   mapping error) are always reported. The screen label is not a filter.
///
/// The three texts match only when they are the whole exception text
/// (optionally behind `Exception: ` / `label: ` prefixes), so a programming
/// error that merely quotes them (`StateError('... Id not found ...')`) is
/// still a real fatal.
final _expectedErrorText = RegExp(
  r'^(?:[^:\n]{1,64}: )*'
  '(?:No Internet connection|Description is required|'
  'beaconNotOpen|Room or item thread access required|'
  'Questions are for the people this request was sent to|Plan text is required|'
  '${RegExp.escape(const RemoteApiRetryLaterException(Duration.zero).toEn)}|'
  '${RegExp.escape(const RequestTimeoutException().toEn)}|'
  r'Plan text must be at most \d+ characters|'
  'Only open requests can be edited|'
  'Image is not attached to this request|'
  r'(?:Auth error: )?there is no correct seed!|'
  r"That seed doesn't match an account\. Check for missing characters|"
  r'Id not found: \[[^\]\n]*\])\.?$',
);

final _screenLoadMessage = RegExp(r'^\[[^\]\n]+\] load failed\b');

final _screenLoadKind = RegExp(r'(?:^|\s)kind=(\w+)');

final _screenLoadRetrying = RegExp(r'(?:^|\n)retrying=1\b');

bool _isExpectedErrorText(String text) =>
    _expectedErrorText.hasMatch(text.trim());

bool _isExpectedScreenLoadMessage(String text) {
  if (!_screenLoadMessage.hasMatch(text)) {
    return false;
  }
  final kind = _screenLoadKind.firstMatch(text)?.group(1);
  if (kind == 'network') {
    return true;
  }
  // A cancelled read or an unavailable server, only for the attempt that is
  // about to be retried. The attempt that gives up has no `retrying=1` and
  // is reported. `kind=server` / `kind=unknown` are never dropped here.
  if (_screenLoadRetrying.hasMatch(text) &&
      (kind == 'cancelled' || kind == 'unavailable')) {
    return true;
  }
  for (final line in text.split('\n')) {
    for (final prefix in const ['detail=', 'error=']) {
      if (line.startsWith(prefix) &&
          _isExpectedErrorText(line.substring(prefix.length))) {
        return true;
      }
    }
  }
  return false;
}

bool isBenignSentryExceptionText(String text) {
  if (_isExpectedErrorText(text) || _isExpectedScreenLoadMessage(text)) {
    return true;
  }
  final lower = text.toLowerCase();
  if (lower.contains('socketexception')) {
    return true;
  }
  // Logged when auth is cleared while in-flight GraphQL requests still run.
  if (lower.contains('key pair is not set')) {
    return true;
  }
  // FCM push SW: CDN/importScripts timeouts, privacy browsers, offline, etc.
  if (lower.contains('failed to register a serviceworker') ||
      lower.contains('timed out while trying to start the service worker')) {
    return true;
  }
  // Flutter web LicenseRegistry / leftover callers loading the root NOTICES
  // asset (Sentry enricher used to trigger this — see reportPackages=false).
  if (lower.contains('unable to load asset: "notices"') ||
      lower.contains("unable to load asset: 'notices'")) {
    return true;
  }
  // web_socket_client Completer race / channel drop — keep while older bundles
  // are cached; drop after deploy of packages/web_socket_client workaround and
  // eventually after https://github.com/felangel/web_socket_client/pull/87 lands.
  if (lower.contains('bad state: future already completed') ||
      lower.contains('websocket connection failed') ||
      lower.contains('websocketchannelexception')) {
    return true;
  }
  // Safari / privacy browsers: clipboard gesture or missing Messaging APIs.
  if (lower.contains('clipboard.setdata failed') ||
      lower.contains('copy_fail') ||
      lower.contains('messaging/unsupported-browser')) {
    return true;
  }
  if (_isBlockedFirebaseJsDynamicImport(text)) {
    return true;
  }
  return false;
}

/// Blocked Firebase JS SDK CDN import (privacy extensions, offline, etc.).
/// Other dynamic-import failures must still report.
bool _isBlockedFirebaseJsDynamicImport(String text) {
  if (!text.contains('Failed to fetch dynamically imported module')) {
    return false;
  }
  return text.contains('gstatic.com/firebasejs/');
}
