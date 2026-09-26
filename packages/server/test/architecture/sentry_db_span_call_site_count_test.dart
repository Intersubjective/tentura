import 'dart:io';

import 'package:test/test.dart';

/// tentura-617.20 (plan §8.10 / H7): `sentryDbSpan` must wrap exactly six
/// SQL call sites under `lib/data/repository` — `pinFact`, `_runEdit`
/// (covers `editText` and `restoreRevision`), `remove`, `listForBeacon` and
/// `history` in `beacon_fact_card_repository.dart`, plus the quoted-fact
/// batch inside `listMessagesEnriched` in `beacon_room_repository.dart`.
/// `setVisibility`, `loadRoomAccess` and `publicFactSnippetsByBeaconIds`
/// must stay unwrapped.
void main() {
  test(
    'sentryDbSpan wraps exactly the six fact/quote SQL call sites',
    () {
      final dir = Directory('lib/data/repository');
      final callSite = RegExp(r'\bsentryDbSpan\s*\(');

      var count = 0;
      final byFile = <String, int>{};
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final matches = callSite.allMatches(file.readAsStringSync()).length;
        if (matches > 0) byFile[file.path] = matches;
        count += matches;
      }

      expect(
        count,
        6,
        reason:
            'expected sentryDbSpan at pinFact, _runEdit, remove, '
            'listForBeacon and history in beacon_fact_card_repository.dart '
            'plus the quote batch in beacon_room_repository.dart '
            'listMessagesEnriched; found: $byFile',
      );
    },
  );
}
