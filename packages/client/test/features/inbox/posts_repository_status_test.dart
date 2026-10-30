// Plan D0: `PostSummary.status` maps the wire smallint (0 open, 6 closed by
// budding) through the real `PostsRepository` and Ferry link chain.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _row(String id, int status) => {
  '__typename': 'v2_PostSummary',
  'id': id,
  'authorId': 'Uauthor000001',
  'authorName': 'Author',
  'authorAvatar': '',
  'rootImageUrl': null,
  'rootExcerpt': 'Who has a ladder?',
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': status == 0,
  'lastMessageAt': null,
  'lastActivityAt': '2026-10-11T08:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'isAuthor': false,
  'status': status,
};

void main() {
  test('myPosts maps open and closed Post status', () async {
    late List<PostSummary> posts;
    await withRemoteWire(
      {
        'MyPosts': {
          '__typename': 'query_root',
          'myPosts': [_row('Bpost00000001', 0), _row('Bpost00000002', 6)],
        },
      },
      <WireSent>[],
      (remote) async {
        posts = await PostsRepository(remote).myPosts();
      },
    );
    expect(posts.first.lastMessageIsRoot, isTrue);
    expect(posts.last.lastMessageIsRoot, isFalse);
    expect(posts.first.status, BeaconStatus.open);
    expect(posts.first.isClosed, isFalse);
    expect(posts.last.status, BeaconStatus.closed);
    expect(posts.last.isClosed, isTrue);
  });

  test('postSummary maps a closed Post', () async {
    late PostSummary? post;
    await withRemoteWire(
      {
        'PostSummary': {
          '__typename': 'query_root',
          'postSummary': _row('Bpost00000002', 6),
        },
      },
      <WireSent>[],
      (remote) async {
        post = await PostsRepository(remote).postSummary('Bpost00000002');
      },
    );
    expect(post?.isClosed, isTrue);
    expect(post?.lastMessageIsRoot, isFalse);
  });
}
