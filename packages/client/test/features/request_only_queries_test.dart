import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _requestOnly = RegExp(r'kind:\s*\{\s*_eq:\s*0\s*\}');

String _read(String path) => File(path).readAsStringSync();

String _stripGraphqlComments(String s) =>
    s.replaceAll(RegExp(r'#[^\n]*'), '');

/// Text inside the parentheses of the root field call `field(`, i.e. its
/// arguments only (never the selection set that follows).
String _rootFieldArgs(String source, String field) {
  final text = _stripGraphqlComments(source);
  final start = text.indexOf(field);
  expect(start, isNonNegative, reason: 'missing $field');
  final open = text.indexOf('(', start);
  expect(open, isNonNegative, reason: '$field has no arguments');
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')' && --depth == 0) return text.substring(open, i);
  }
  fail('unbalanced parentheses after $field');
}

void _expectRequestOnly(String path, String field) {
  expect(
    _requestOnly.hasMatch(_rootFieldArgs(_read(path), field)),
    isTrue,
    reason: '$field in $path must filter to kind 0 in its arguments',
  );
}

Iterable<File> _handWrittenDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where(
      (f) =>
          !f.path.contains('/_g/') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.freezed.dart') &&
          !f.path.endsWith('.config.dart') &&
          !f.path.endsWith('.gr.dart') &&
          !f.path.contains('lib/ui/l10n/'),
    );

void main() {
  group('Request-only GraphQL documents', () {
    const myWork = 'lib/features/my_work/data/gql/my_work_fetch.graphql';
    const profile =
        'lib/features/profile_view/data/gql/profile_shared_beacons_fetch.graphql';

    test('My Work authored list excludes Posts', () {
      _expectRequestOnly(myWork, 'authoredNonArchived: beacon(');
    });

    test('My Work help-offered list excludes Posts', () {
      _expectRequestOnly(myWork, 'helpOfferedNonArchived: beacon_help_offer(');
    });

    test('profile forwarded-to-user list excludes Posts', () {
      _expectRequestOnly(profile, 'beacon_forward_edge(');
    });

    test('profile co-committed list excludes Posts', () {
      final s = _read(profile);
      final from = s.indexOf('query ProfileCoCommitted');
      expect(from, isNonNegative);
      final args = _rootFieldArgs(s.substring(from), 'beacon(');
      expect(_requestOnly.hasMatch(args), isTrue);
    });

    test('pinned favorites fetch excludes Posts', () {
      _expectRequestOnly(
        'lib/features/favorites/data/gql/beacon_fetch_pinned.graphql',
        'beacon_pinned(',
      );
    });
  });

  group('Beacon model GraphQL fragments select Post fields', () {
    const fields = [
      'kind',
      'forward_policy',
      'last_activity_at',
      'post_root_message_id',
      'viewer_can_forward',
    ];
    // Fragments whose selection must carry the new fields: the base one, and
    // each variant either selects them itself or spreads the base fragment.
    const files = [
      'lib/data/gql/beacon_model.graphql',
      'lib/features/beacon/data/gql/beacon_model_with_admitted_helpers.graphql',
      'lib/features/my_work/data/gql/beacon_model_with_help_offer_users.graphql',
    ];
    test('the base fragment itself selects every new field', () {
      final s = _stripGraphqlComments(_read(files.first));
      for (final field in fields) {
        expect(
          RegExp('^\\s*$field\\s*\$', multiLine: true).hasMatch(s),
          isTrue,
          reason: 'base fragment lacks $field',
        );
      }
    });

    test('variant fragments select the new fields themselves', () {
      for (final f in files.skip(1)) {
        final s = _stripGraphqlComments(_read(f));
        for (final field in fields) {
          expect(
            RegExp('^\\s*$field\\s*\$', multiLine: true).hasMatch(s),
            isTrue,
            reason: '$f lacks $field',
          );
        }
      }
    });
  });

  group('Forward entry points use viewerCanForward', () {
    // Any Beacon-valued receiver reading allowsForward is a Forward decision
    // made from lifecycle alone; wire/receipt/status receivers are fine.
    final beaconAllowsForward = RegExp(
      r'(\bbeacon\??|\bb|\bvm\.beacon)\.allowsForward\b',
    );

    test('no file under lib reads Beacon.allowsForward', () {
      final offenders = <String>[
        for (final f in _handWrittenDartFiles())
          if (_read(f.path)
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('///'))
              .any(beaconAllowsForward.hasMatch))
            f.path,
      ];
      expect(offenders, isEmpty);
    });

    const gatedFiles = [
      'lib/features/inbox/ui/screen/inbox_watching_screen.dart',
      'lib/features/inbox/ui/screen/inbox_rejected_screen.dart',
      'lib/features/inbox/ui/widget/request_attention_card.dart',
      'lib/features/inbox/ui/widget/request_attention_card_mapper.dart',
      'lib/features/beacon/ui/widget/beacon_overflow_menu.dart',
      'lib/features/my_work/ui/widget/my_work_cards.dart',
      'lib/features/forward/ui/bloc/forward_cubit.dart',
      'lib/features/forward/ui/widget/forward_recipient_picker.dart',
      'lib/features/beacon_view/ui/widget/beacon_now_surface.dart',
      'lib/features/beacon_view/ui/util/beacon_hud_derivation.dart',
      'lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart',
      'lib/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart',
    ];
    for (final f in gatedFiles) {
      test('$f decides Forward from viewerCanForward', () {
        expect(_read(f).contains('viewerCanForward'), isTrue);
      });
    }
  });
}
