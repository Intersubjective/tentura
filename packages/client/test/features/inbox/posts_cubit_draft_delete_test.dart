// The Posts list reloads itself when a Beacon is deleted through
// BeaconRepository (the event Request drafts use to leave My Work), so a Post
// draft deleted elsewhere drops out of `drafts` at once, with no realtime
// change from the server. After the cubit is closed a delete event does
// nothing.
//
// Real path: BeaconRepository.delete goes over the faked HTTP wire, and the
// list is re-read through PostsRepository's `MyPosts` mapper into PostsCubit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'posts_tab_wire_test_support.dart';

const _draftId = 'Bdraftbike01';
const _otherDraftId = 'Bdraftbook01';

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: _draftId,
      excerpt: 'Велосипед на выходные',
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(minutes: 5)),
    ),
    myPostsWireRow(
      id: _otherDraftId,
      excerpt: 'Книги для обмена',
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(hours: 2)),
    ),
  ];
}

void main() {
  testWidgets(
    'a deleted Beacon makes the Posts list refetch and drop its draft',
    (tester) async {
      await withPostsTab(
        tester,
        size: const Size(375, 667),
        wire: PostsTabWire(_rows()),
        body: (h) async {
          // The fake server pushes no realtime change after the delete.
          h.wire.onWrite = null;
          expect(
            [for (final d in h.cubit.state.drafts) d.id]..sort(),
            [_draftId, _otherDraftId]..sort(),
          );
          final before = h.wire.calls('MyPosts').length;

          await h.beacons.delete(_draftId);
          await settlePostsTab(tester);

          expect(h.wire.calls('MyPosts').length, greaterThan(before));
          expect([for (final d in h.cubit.state.drafts) d.id], [_otherDraftId]);
        },
      );
    },
  );

  testWidgets(
    'a delete event after the Posts cubit is closed neither refetches nor '
    'throws',
    (tester) async {
      await withPostsTab(
        tester,
        size: const Size(375, 667),
        wire: PostsTabWire(_rows()),
        body: (h) async {
          h.wire.onWrite = null;
          // The subscription is live first: this delete is seen.
          final beforeLive = h.wire.calls('MyPosts').length;
          await h.beacons.delete(_draftId);
          await settlePostsTab(tester);
          expect(
            h.wire.calls('MyPosts').length,
            greaterThan(beforeLive),
            reason: 'a live cubit refetches',
          );

          await h.cubit.close();
          final afterClose = h.wire.calls('MyPosts').length;
          await h.beacons.delete(_otherDraftId);
          await settlePostsTab(tester);

          expect(h.wire.calls('MyPosts').length, afterClose);
        },
      );
    },
  );
}
