import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// Whether [error] is an expected, user-facing failure that should not
/// become a Sentry issue (connectivity loss, session expiry, etc.).
bool isBenignSentryThrowable(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is ConnectionUplinkException ||
      error is AuthSessionLostException ||
      error is AuthenticationNoKeyException ||
      error is SessionAuthRejectedException) {
    return true;
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
  if (isBenignSentryThrowable(synthetic)) {
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

bool isBenignSentryExceptionText(String text) {
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
  return false;
}
