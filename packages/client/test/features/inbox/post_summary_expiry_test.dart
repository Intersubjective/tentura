import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';

import '../../support/remote_wire_harness.dart';

final _now = DateTime.utc(2026, 10, 26, 12);

Map<String, dynamic> _row(String? expiresAt) => {
  '__typename': 'v2_PostSummary',
  'id': 'Bpost00000001',
  'authorId': 'Uauthor000001',
  'authorName': 'Author',
  'authorAvatar': '',
  'rootImageUrl': null,
  'rootExcerpt': 'Who has a ladder?',
  'lastMessageExcerpt': null,
  'lastMessageAt': null,
  'lastActivityAt': '2026-10-26T11:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'isAuthor': false,
  'status': 0,
  'expiresAt': expiresAt,
};

void main() {
  group('Post summary expiry mapping', () {
    for (final expiresAt in ['2026-10-26T16:00:00+02:00', null]) {
      test('myPosts preserves expiry $expiresAt', () async {
        await withRemoteWire(
          {
            'MyPosts': {
              '__typename': 'query_root',
              'myPosts': [_row(expiresAt)],
            },
          },
          <WireSent>[],
          (remote) async {
            final posts = await PostsRepository(remote).myPosts();
            expect(
              posts.single.expiresAt,
              expiresAt == null ? null : DateTime.utc(2026, 10, 26, 14),
            );
          },
        );
      });

      test('postSummary preserves expiry $expiresAt', () async {
        await withRemoteWire(
          {
            'PostSummary': {
              '__typename': 'query_root',
              'postSummary': _row(expiresAt),
            },
          },
          <WireSent>[],
          (remote) async {
            final post = await PostsRepository(
              remote,
            ).postSummary('Bpost00000001');
            expect(post, isNotNull);
            expect(
              post!.expiresAt,
              expiresAt == null ? null : DateTime.utc(2026, 10, 26, 14),
            );
          },
        );
      });
    }
  });

  group('Post summary archive policy', () {
    for (final status in BeaconStatus.values) {
      for (final entry in <String, DateTime?>{
        'missing': null,
        'future': _now.add(const Duration(microseconds: 1)),
        'equal': _now,
        'past': _now.subtract(const Duration(microseconds: 1)),
      }.entries) {
        test('${status.name} with ${entry.key} expiry', () {
          final post = PostSummary(
            id: 'Bpost00000001',
            authorId: 'Uauthor000001',
            authorName: 'Author',
            // Activity does not extend the fixed publication deadline.
            lastActivityAt: _now,
            status: status,
            expiresAt: entry.value,
          );
          final expected =
              status == BeaconStatus.closed ||
              (status == BeaconStatus.open &&
                  (entry.key == 'equal' || entry.key == 'past'));
          expect(post.isArchivedAt(_now), expected);
        });
      }
    }
  });
}
