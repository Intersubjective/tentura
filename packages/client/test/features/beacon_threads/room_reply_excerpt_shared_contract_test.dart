@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/util/room_reply_excerpt.dart'
    as client;

import '../../support/room_reply_excerpt_delegation_guard.dart';

// Coverage: ASCII, Cyrillic and supplementary-plane emoji at 159/160/161
// runes; mixed whitespace; blank input; poll fallback and body precedence;
// one shared truncation owner reachable from both public entry points.
// Siblings: surface = client preview/server snapshot; locale = EN/RU text;
// width = 375x667 RU in room_reply_excerpt_real_path_test.dart. Input devices,
// roles, lifecycle state, freshness and network variants are n/a: the excerpt
// is a synchronous string policy independent of those conditions.
// Real-path coverage: room_message_reply_readback_pg_test.dart,
// "reply snapshots omit a combining sequence crossing the rune limit".
// It inserts a parent and reply through the real repository and reads the
// computed snapshot back from PostgreSQL. Client coverage is in
// room_reply_excerpt_real_path_test.dart: HTTP -> Ferry -> repository ->
// RoomCubit -> reply composer banner; no hand-built message entity.
void main() {
  test(
    'client previews and server snapshots use one shared rune excerpt policy',
    () async {
      final root = Directory.current.absolute.parent.parent.uri;
      const author = Profile(id: 'author', displayName: 'Anna');

      void expectExcerpt(String body, String? expected, {String? question}) {
        final message = RoomMessage(
          id: 'message',
          beaconId: 'beacon',
          authorId: author.id,
          author: author,
          body: body,
          createdAt: DateTime.utc(2026),
          linkedPollingId: question == null ? null : 'poll',
          pollDataJson: question == null
              ? null
              : jsonEncode({
                  'id': 'poll',
                  'question': question,
                  'pollType': 'single',
                  'totalVotes': 0,
                  'variants': const <Object>[],
                }),
        );
        final preview = client.roomReplyExcerpt(message);
        expect(preview, expected, reason: 'client: ${jsonEncode(body)}');
      }

      for (final rune in const ['a', 'я', '😀']) {
        for (final length in const [159, 160, 161]) {
          final body = rune * length;
          expectExcerpt(body, length <= 160 ? body : '${rune * 160}…');
        }
      }
      // Each boundary contains all three scripts/widths, with different tails.
      const mixedPrefix =
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'; // 159 runes, 212 UTF-16 code units.
      expectExcerpt(mixedPrefix, mixedPrefix);
      expectExcerpt('$mixedPrefixЖ', '$mixedPrefixЖ');
      expectExcerpt('$mixedPrefixЖz', '$mixedPrefixЖ…');
      expectExcerpt('$mixedPrefix😀z', '$mixedPrefix😀…');
      // Preserve the existing rune contract: a two-rune flag at the cut keeps
      // its first regional indicator, but never splits its UTF-16 surrogate.
      expectExcerpt('${'a' * 159}🇺🇸', '${'a' * 159}🇺…');
      // Mixed-width text puts a supplementary-plane rune exactly at the cut.
      expectExcerpt('${'я' * 159}😀x', '${'я' * 159}😀…');
      // A complete combining sequence inside the retained 160-rune prefix.
      expectExcerpt('${'a' * 158}e\u0301x', '${'a' * 158}e\u0301…');
      expectExcerpt(
        ' \t\r\n\u000b\u000c hello\t\r\nмир  😀 \n',
        'hello мир 😀',
      );
      expectExcerpt(' \t\r\n\u000b\u000c', null);
      expectExcerpt('', null);
      expectExcerpt(' \t', '📊 Как дела?', question: ' Как\nдела? ');
      expectExcerpt('', '📊 ${'я' * 158}…', question: 'я' * 159);
      expectExcerpt('body', 'body', question: 'ignored');

      expect(
        await excerptDelegationViolations(root),
        isEmpty,
        reason:
            'Both public APIs must return the same shared truncation '
            'result; local excerpt construction must be removed.',
      );
    },
  );
  test(
    'client excerpts omit a combining sequence crossing the rune limit',
    () {
      const prefix =
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'; // 159 runes.
      const body = '${prefix}e\u0301tail';
      final actual = client.roomReplyExcerpt(
        RoomMessage(
          id: 'message',
          beaconId: 'beacon',
          authorId: 'author',
          author: const Profile(id: 'author', displayName: 'Anna'),
          body: body,
          createdAt: DateTime.utc(2026),
        ),
      );
      expect(
        actual,
        '$prefix…',
        reason:
            'Do not retain a bare base letter '
            'when its combining accent falls beyond the 160-rune budget.',
      );
    },
  );
}
