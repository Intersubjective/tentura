// The Posts tab has a filter beside its title, like My Work: «Активные»
// (default: pinned and live Posts), «Мои» (Posts the viewer wrote, live and
// archived), «Черновики» (the viewer's unsent drafts) and «Архив» (Posts
// whose lifetime ended). A draft is never listed under «Активные»; that view
// links to the drafts with one «Черновики: N» row, or, when it is empty, with
// a «Черновики (N)» empty-state action.
//
// Every test sends the real `myPosts` transport response through the mapper,
// PostsCubit and the real Conversations screen, at phone and desktop widths.
// UI copy is asserted verbatim in Russian.

import 'package:flutter_test/flutter_test.dart';

import 'posts_tab_wire_test_support.dart';

const _pinned = 'Закреплённый пост Анны';
const _myLive = 'Мой живой пост';
const _otherLive = 'Чужой живой пост';
const _myArchived = 'Мой архивный пост';
const _otherArchived = 'Чужой архивный пост';
const _draftBike = 'Велосипед на выходные';
const _draftBooks = 'Книги для обмена';

const _published = [_pinned, _myLive, _otherLive, _myArchived, _otherArchived];
const _drafts = [_draftBike, _draftBooks];

/// Seven Posts: pinned, live and archived ones by the viewer and by others,
/// and two of the viewer's drafts (status 3).
List<Map<String, dynamic>> _mixedRows({bool withDrafts = true}) {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: 'Bpinned00001',
      excerpt: _pinned,
      lastActivityAt: now.subtract(const Duration(hours: 3)),
      pinnedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 20)),
    ),
    myPostsWireRow(
      id: 'Bmylive00001',
      excerpt: _myLive,
      isAuthor: true,
      lastActivityAt: now.subtract(const Duration(minutes: 10)),
      expiresAt: now.add(const Duration(hours: 30)),
    ),
    myPostsWireRow(
      id: 'Botherlive01',
      excerpt: _otherLive,
      lastActivityAt: now.subtract(const Duration(minutes: 20)),
      expiresAt: now.add(const Duration(hours: 40)),
    ),
    myPostsWireRow(
      id: 'Bmyarchive01',
      excerpt: _myArchived,
      isAuthor: true,
      lastActivityAt: now.subtract(const Duration(days: 4)),
      expiresAt: now.subtract(const Duration(days: 1)),
    ),
    myPostsWireRow(
      id: 'Botherarch01',
      excerpt: _otherArchived,
      lastActivityAt: now.subtract(const Duration(days: 5)),
      expiresAt: now.subtract(const Duration(days: 2)),
    ),
    if (withDrafts) ...[
      myPostsWireRow(
        id: 'Bdraftbike01',
        excerpt: _draftBike,
        isAuthor: true,
        status: 3,
        lastActivityAt: now.subtract(const Duration(minutes: 5)),
      ),
      myPostsWireRow(
        id: 'Bdraftbook01',
        excerpt: _draftBooks,
        isAuthor: true,
        status: 3,
        lastActivityAt: now.subtract(const Duration(hours: 2)),
      ),
    ],
  ];
}

/// Only Posts by others, and one draft: «Активные» shows two Posts, «Мои»
/// and «Архив» show nothing.
List<Map<String, dynamic>> _othersLiveAndOneDraft() {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: 'Botherlive01',
      excerpt: _otherLive,
      lastActivityAt: now.subtract(const Duration(minutes: 20)),
      expiresAt: now.add(const Duration(hours: 40)),
    ),
    myPostsWireRow(
      id: 'Bdraftbike01',
      excerpt: _draftBike,
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(minutes: 5)),
    ),
  ];
}

/// Only archived Posts and drafts: «Активные» has no rows of its own.
List<Map<String, dynamic>> _archivedAndDrafts(int drafts) {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: 'Botherarch01',
      excerpt: _otherArchived,
      lastActivityAt: now.subtract(const Duration(days: 5)),
      expiresAt: now.subtract(const Duration(days: 2)),
    ),
    for (var i = 0; i < drafts; i++)
      myPostsWireRow(
        id: 'Bdraft0000$i',
        excerpt: _drafts[i],
        isAuthor: true,
        status: 3,
        lastActivityAt: now.subtract(Duration(minutes: 5 + i)),
      ),
  ];
}

void _expectShown(List<String> excerpts) {
  for (final excerpt in excerpts) {
    expect(postRowWith(excerpt), findsOneWidget, reason: '«$excerpt» listed');
  }
}

void _expectAbsent(List<String> excerpts) {
  for (final excerpt in excerpts) {
    expect(find.text(excerpt), findsNothing, reason: '«$excerpt» not listed');
  }
}

void main() {
  for (final viewport in postsTabViewports) {
    group('Posts tab filter (${viewport.name})', () {
      testWidgets(
        'opens on «Активные»: pinned and live Posts, never drafts or archive',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              _expectShown([_pinned, _myLive, _otherLive]);
              _expectAbsent([..._drafts, _myArchived, _otherArchived]);
              expect(
                postsFilterControl('Активные'),
                findsOneWidget,
                reason: 'the filter beside the title starts on «Активные»',
              );
            },
          );
        },
      );

      testWidgets(
        'the menu offers Активные, Мои, Черновики, Архив in order, no counts',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              await tester.tap(postsFilterControl('Активные'));
              await settlePostsTab(tester);

              final labels = openMenuLabels(tester);
              expect(labels, ['Активные', 'Мои', 'Черновики', 'Архив']);
              for (final label in labels) {
                expect(
                  label,
                  isNot(matches(RegExp(r'\d'))),
                  reason: 'the filter menu shows no counts',
                );
              }
            },
          );
        },
      );

      testWidgets(
        "«Мои» lists the viewer's live and archived Posts, no drafts",
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              await pickPostsFilter(tester, current: 'Активные', next: 'Мои');

              expect(postsFilterControl('Мои'), findsOneWidget);
              expect(postsFilterControl('Активные'), findsNothing);
              _expectShown([_myLive, _myArchived]);
              _expectAbsent([
                _pinned,
                _otherLive,
                _otherArchived,
                ..._drafts,
              ]);
            },
          );
        },
      );

      testWidgets(
        "«Черновики» lists only the viewer's drafts, as draft rows",
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );

              expect(postsFilterControl('Черновики'), findsOneWidget);
              _expectShown(_drafts);
              _expectAbsent(_published);
              for (final excerpt in _drafts) {
                expect(
                  find.descendant(
                    of: postRowWith(excerpt),
                    matching: find.text('Черновик'),
                  ),
                  findsOneWidget,
                  reason: '«$excerpt» is labelled «Черновик»',
                );
              }
            },
          );
        },
      );

      testWidgets(
        '«Архив» lists only Posts whose lifetime ended, no live or drafts',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Архив',
              );

              expect(postsFilterControl('Архив'), findsOneWidget);
              _expectShown([_myArchived, _otherArchived]);
              _expectAbsent([_pinned, _myLive, _otherLive, ..._drafts]);
            },
          );
        },
      );

      testWidgets('switching back to «Активные» restores its rows', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_mixedRows()),
          body: (h) async {
            await pickPostsFilter(tester, current: 'Активные', next: 'Архив');
            await pickPostsFilter(tester, current: 'Архив', next: 'Активные');

            expect(postsFilterControl('Активные'), findsOneWidget);
            _expectShown([_pinned, _myLive, _otherLive]);
            _expectAbsent([..._drafts, _myArchived, _otherArchived]);
          },
        );
      });

      testWidgets(
        '«Активные» starts with one «Черновики: 2» row that opens the drafts',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_mixedRows()),
            body: (h) async {
              final link = find.text('Черновики: 2', findRichText: true);
              expect(link, findsOneWidget);
              expect(
                tester.getTopLeft(link).dy,
                lessThan(tester.getTopLeft(postRowWith(_pinned)).dy),
                reason: 'the drafts row sits above every Post row',
              );

              await tester.tap(link);
              await settlePostsTab(tester);

              expect(postsFilterControl('Черновики'), findsOneWidget);
              _expectShown(_drafts);
              _expectAbsent(_published);
            },
          );
        },
      );

      testWidgets('«Активные» shows no drafts row when there are no drafts', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_mixedRows(withDrafts: false)),
          body: (h) async {
            expect(postsFilterControl('Активные'), findsOneWidget);
            _expectShown([_pinned, _myLive, _otherLive]);
            expect(
              find.textContaining('Черновики', findRichText: true),
              findsNothing,
            );
          },
        );
      });

      testWidgets(
        'an empty «Активные» offers «Черновики (2)» in its empty state',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_archivedAndDrafts(2)),
            body: (h) async {
              expect(postsFilterControl('Активные'), findsOneWidget);
              expect(postsEmptyState, findsOneWidget);
              _expectAbsent([_otherArchived, ..._drafts]);
              final action = find.descendant(
                of: postsEmptyState,
                matching: find.text('Черновики (2)'),
              );
              expect(action, findsOneWidget);

              await tester.tap(action);
              await settlePostsTab(tester);

              expect(postsFilterControl('Черновики'), findsOneWidget);
              _expectShown(_drafts);
            },
          );
        },
      );

      testWidgets('a filter with no rows shows an empty state, not a list', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_othersLiveAndOneDraft()),
          body: (h) async {
            await pickPostsFilter(tester, current: 'Активные', next: 'Мои');
            expect(postsEmptyState, findsOneWidget);
            _expectAbsent([_otherLive, _draftBike]);

            await pickPostsFilter(tester, current: 'Мои', next: 'Архив');
            expect(postsEmptyState, findsOneWidget);
            _expectAbsent([_otherLive, _draftBike]);

            await pickPostsFilter(tester, current: 'Архив', next: 'Черновики');
            expect(postsEmptyState, findsNothing);
            _expectShown([_draftBike]);
          },
        );
      });

      testWidgets('with no drafts, «Черновики» shows an empty state', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_mixedRows(withDrafts: false)),
          body: (h) async {
            await pickPostsFilter(
              tester,
              current: 'Активные',
              next: 'Черновики',
            );
            expect(postsEmptyState, findsOneWidget);
            _expectAbsent(_published);
          },
        );
      });
    });
  }
}
