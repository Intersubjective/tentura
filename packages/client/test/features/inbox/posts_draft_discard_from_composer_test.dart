// A Post draft discarded from the composer's «Keep this draft?» leave dialog
// leaves the Posts tab's Drafts list, and lowers the «Drafts: N» row, at once:
// no realtime push from the server and no reload. Keep leaves the row, and a
// discard the server refuses leaves the composer open and the row in place.
//
// Real path: the Post composer (PostCreateScreen over BeaconCreateCubit and
// BeaconRepository) and the Posts tab (ConversationsScreen over PostsCubit,
// PostsCase and PostsRepository) share one Ferry client; only HTTP is faked.
// The fake server pushes no realtime change after a write, so the list can
// only learn of the discard from the repository's own delete event.
//
// Run at phone width in Russian and at desktop width in English.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'posts_tab_wire_test_support.dart';

const _draftId = 'Bdraftbike01';
const _otherDraftId = 'Bdraftbook01';
const _draftText = 'Велосипед на выходные';
const _otherDraftText = 'Книги для обмена';
const _liveText = 'Мой живой пост';

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: 'Bmylive00001',
      excerpt: _liveText,
      isAuthor: true,
      lastActivityAt: now.subtract(const Duration(minutes: 10)),
      expiresAt: now.add(const Duration(hours: 30)),
    ),
    myPostsWireRow(
      id: _draftId,
      excerpt: _draftText,
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(minutes: 5)),
    ),
    myPostsWireRow(
      id: _otherDraftId,
      excerpt: _otherDraftText,
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(hours: 2)),
    ),
  ];
}

const _runs = <({String name, Size size, Locale locale})>[
  (name: 'phone 375×667 RU', size: Size(375, 667), locale: Locale('ru')),
  (name: 'desktop 1280×800 EN', size: Size(1280, 800), locale: Locale('en')),
];

/// Opens draft A from the Drafts filter, then closes the composer so the
/// «Keep this draft?» leave dialog is up.
Future<void> _openDraftAndAskToLeave(
  WidgetTester tester,
  PostsTabHarness h,
  L10n l10n,
) async {
  // The composer's own writes must not reach the list as a realtime change.
  h.wire.onWrite = null;
  await pickPostsFilter(
    tester,
    current: l10n.postsFilterActive,
    next: l10n.postsFilterDrafts,
  );
  await tester.tap(find.text(_draftText));
  await settlePostsTab(tester);
  expect(h.composerDraftIds, [_draftId]);
  expect(find.byType(PostCreateScreen), findsOneWidget);

  await tester.tap(
    find.descendant(
      of: find.byType(PostCreateScreen),
      matching: find.byIcon(Icons.close),
    ),
  );
  await settlePostsTab(tester);
  expect(find.text(l10n.beaconCreateLeaveTitle), findsOneWidget);
}

Future<void> _tapLeaveDialog(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(
    find.descendant(of: find.byType(Dialog), matching: find.text(label)),
  );
  await settlePostsTab(tester);
}

void main() {
  for (final run in _runs) {
    final l10n = lookupL10n(run.locale);

    group('Post draft left from the composer (${run.name})', () {
      testWidgets(
        'Discard removes the draft row from the Drafts list and lowers the '
        'drafts count without a reload',
        (tester) async {
          await withPostsTab(
            tester,
            size: run.size,
            locale: run.locale,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              expect(
                find.text(l10n.postsDraftsCount(2), findRichText: true),
                findsOneWidget,
              );
              final myPostsBefore = h.wire.calls('MyPosts').length;

              await _openDraftAndAskToLeave(tester, h, l10n);
              await _tapLeaveDialog(tester, l10n.beaconCreateLeaveDiscard);

              expect(h.wire.deletedIds, [_draftId]);
              expect(
                find.byType(PostCreateScreen),
                findsNothing,
                reason: 'a discarded draft closes the composer',
              );
              expect(
                h.wire.calls('MyPosts').length,
                greaterThan(myPostsBefore),
                reason: 'the list refetched itself after the discard',
              );
              expect(find.text(_draftText), findsNothing);
              expect(postRowWith(_otherDraftText), findsOneWidget);

              await pickPostsFilter(
                tester,
                current: l10n.postsFilterDrafts,
                next: l10n.postsFilterActive,
              );
              expect(
                find.text(l10n.postsDraftsCount(1), findRichText: true),
                findsOneWidget,
              );
              expect(
                find.text(l10n.postsDraftsCount(2), findRichText: true),
                findsNothing,
              );
            },
          );
        },
      );

      testWidgets(
        'Keep draft leaves the draft row and the drafts count as they were',
        (tester) async {
          await withPostsTab(
            tester,
            size: run.size,
            locale: run.locale,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _openDraftAndAskToLeave(tester, h, l10n);
              await _tapLeaveDialog(tester, l10n.beaconCreateLeaveKeepDraft);

              expect(h.wire.deletedIds, isEmpty);
              expect(find.byType(PostCreateScreen), findsNothing);
              expect(postRowWith(_draftText), findsOneWidget);
              expect(postRowWith(_otherDraftText), findsOneWidget);

              await pickPostsFilter(
                tester,
                current: l10n.postsFilterDrafts,
                next: l10n.postsFilterActive,
              );
              expect(
                find.text(l10n.postsDraftsCount(2), findRichText: true),
                findsOneWidget,
              );
            },
          );
        },
      );

      testWidgets(
        'a Discard the server refuses shows the error, keeps the composer '
        'open and keeps the draft row and count',
        (tester) async {
          await withPostsTab(
            tester,
            size: run.size,
            locale: run.locale,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _openDraftAndAskToLeave(tester, h, l10n);
              h.wire.deletesSucceed = false;
              await _tapLeaveDialog(tester, l10n.beaconCreateLeaveDiscard);

              expect(h.wire.deletedIds, [_draftId], reason: 'delete was tried');
              expect(h.effects.emitted.whereType<ShowError>(), isNotEmpty);
              expect(
                find.byType(PostCreateScreen),
                findsOneWidget,
                reason: 'a failed discard keeps the composer open',
              );

              // Leave for real by keeping the draft, then read the list.
              await tester.tap(
                find.descendant(
                  of: find.byType(PostCreateScreen),
                  matching: find.byIcon(Icons.close),
                ),
              );
              await settlePostsTab(tester);
              await _tapLeaveDialog(tester, l10n.beaconCreateLeaveKeepDraft);

              expect(find.byType(PostCreateScreen), findsNothing);
              expect(postRowWith(_draftText), findsOneWidget);
              expect(postRowWith(_otherDraftText), findsOneWidget);
              await pickPostsFilter(
                tester,
                current: l10n.postsFilterDrafts,
                next: l10n.postsFilterActive,
              );
              expect(
                find.text(l10n.postsDraftsCount(2), findRichText: true),
                findsOneWidget,
              );
            },
          );
        },
      );
    });
  }
}
