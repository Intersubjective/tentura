import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/util/room_reply_excerpt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const author = Profile(id: 'a1', displayName: 'Anna');
  final baseTime = DateTime.utc(2026, 6, 30, 12);

  RoomMessage message({String body = 'hello'}) => RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: author.id,
        author: author,
        body: body,
        createdAt: baseTime,
      );

  test('roomReplyExcerpt collapses whitespace and truncates on rune boundary', () {
    expect(roomReplyExcerpt(message(body: '  hello\nworld  ')), 'hello world');
    final longBody = 'x' * 161;
    expect(roomReplyExcerpt(message(body: longBody))!.length, 161);
    expect(roomReplyExcerpt(message(body: longBody))!.endsWith('…'), isTrue);
  });

  test('roomReplyExcerpt returns null for blank body', () {
    expect(roomReplyExcerpt(message(body: '   ')), isNull);
  });

  test('roomReplyExcerptFor prefers non-blank excerpt', () {
    final l10n = lookupL10n(const Locale('en'));
    expect(
      roomReplyExcerptFor(
        excerpt: '  quoted text  ',
        hasAttachments: true,
        l10n: l10n,
      ),
      'quoted text',
    );
  });

  test('roomReplyExcerptFor falls back to attachment label', () {
    final l10n = lookupL10n(const Locale('en'));
    expect(
      roomReplyExcerptFor(
        excerpt: null,
        hasAttachments: true,
        l10n: l10n,
      ),
      l10n.beaconRoomReplyAttachmentExcerpt,
    );
  });

  test('roomReplyExcerptFor falls back to unavailable label', () {
    final l10n = lookupL10n(const Locale('en'));
    expect(
      roomReplyExcerptFor(
        excerpt: '',
        hasAttachments: false,
        l10n: l10n,
      ),
      l10n.beaconRoomReplyOriginalUnavailable,
    );
  });

  // #377: a poll has no body; the quote is its question, as the server sends.
  test('roomReplyExcerpt quotes a poll by its question', () {
    final poll = message(body: '').copyWith(
      linkedPollingId: 'p1',
      pollDataJson: jsonEncode({
        'id': 'p1',
        'question': ' Which day\nworks? ',
        'pollType': 'single',
        'totalVotes': 0,
        'variants': <Object>[],
      }),
    );
    expect(roomReplyExcerpt(poll), '📊 Which day works?');
  });
}
