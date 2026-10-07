import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';

const _nullCheckText = 'Null check operator used on a null value';

/// Exact context string the framework's `WidgetsBinding.handleViewFocusChanged`
/// reports (compiled web bundle: `while dispatching notifications for
/// WidgetsBindingObserver.didChangeViewFocus`).
const _viewFocusContext =
    'while dispatching notifications for '
    'WidgetsBindingObserver.didChangeViewFocus';

/// Throws the same `TypeError` the Flutter web engine raises from
/// `FocusTraversalPolicy._findInitialFocus` when the semantics tree is
/// mid-update.
Object _realNullCheckError() {
  final Object? nothing = DateTime.now().year > 0 ? null : Object();
  try {
    // ignore: unnecessary_non_null_assertion
    nothing!;
  } catch (e) {
    return e;
  }
  throw StateError('null check did not throw');
}

SentryEvent _eventWith({
  required String type,
  required String value,
  required String library,
  required String context,
}) => SentryEvent(
  exceptions: [SentryException(type: type, value: value)],
  contexts: Contexts()
    ..['flutter_error_details'] = {
      'library': library,
      'context': context,
    },
);

void main() {
  group('framework view-focus traversal null check (Sentry filter)', () {
    test('real null-check TypeError while dispatching didChangeViewFocus '
        'is dropped', () {
      final error = _realNullCheckError();
      expect(error.toString(), contains(_nullCheckText));

      final hint = Hint();
      hint.set(
        TypeCheckHint.syntheticException,
        FlutterErrorDetails(
          exception: error,
          library: 'widgets library',
          context: ErrorDescription(_viewFocusContext),
        ),
      );

      expect(isBenignSentryEvent(SentryEvent(), hint), isTrue);
    });

    test('event carrying the null-check text and view-focus dispatch '
        'context is dropped', () {
      final event = _eventWith(
        type: 'TypeError',
        value: _nullCheckText,
        library: 'widgets library',
        context: _viewFocusContext,
      );

      expect(isBenignSentryEvent(event, Hint()), isTrue);
    });

    test('event whose value is the full serialized TypeError string is '
        'dropped', () {
      final event = _eventWith(
        type: 'TypeError',
        value:
            'TypeError: $_nullCheckText\n'
            '    at FocusTraversalPolicy._findInitialFocus',
        library: 'widgets library',
        context: _viewFocusContext,
      );

      expect(isBenignSentryEvent(event, Hint()), isTrue);
    });

    test('null check raised in an unrelated context still reports', () {
      final event = _eventWith(
        type: 'TypeError',
        value: _nullCheckText,
        library: 'widgets library',
        context: 'building BeaconViewScreen',
      );
      expect(isBenignSentryEvent(event, Hint()), isFalse);

      final hint = Hint();
      hint.set(
        TypeCheckHint.syntheticException,
        FlutterErrorDetails(
          exception: _realNullCheckError(),
          library: 'widgets library',
          context: ErrorDescription('while building a widget'),
        ),
      );
      expect(isBenignSentryEvent(SentryEvent(), hint), isFalse);
    });

    test('null check with no Flutter error context still reports', () {
      final event = SentryEvent(
        exceptions: [SentryException(type: 'TypeError', value: _nullCheckText)],
      );

      expect(isBenignSentryEvent(event, Hint()), isFalse);
    });

    test('other errors during view-focus dispatch still report', () {
      final event = _eventWith(
        type: 'StateError',
        value: 'Bad state: observer misbehaved',
        library: 'widgets library',
        context: _viewFocusContext,
      );

      expect(isBenignSentryEvent(event, Hint()), isFalse);
    });

    test('filter source documents the rationale with the Sentry issue and an '
        'upstream Flutter issue link', () {
      final source = File(
        'lib/app/sentry/sentry_benign_filter.dart',
      ).readAsStringSync();

      expect(source, contains('TENTURA-CLIENT-37'));
      expect(source, contains('didChangeViewFocus'));
      expect(
        RegExp(
          r'https://github\.com/flutter/(flutter|engine)/(issues|pull)/\d+',
        ).hasMatch(source),
        isTrue,
        reason: 'link the upstream Flutter issue that justifies the filter',
      );
    });
  });
}
