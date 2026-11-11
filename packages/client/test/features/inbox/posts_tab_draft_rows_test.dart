// A Post draft in the Posts tab's «Черновики» filter is a muted Post row
// labelled «Черновик» with the draft's text and no lifetime marker. Tapping
// it, or «Изменить» in its trailing overflow menu, opens the Post composer on
// that draft; «Удалить» asks the Post discard question first and only then
// deletes the draft on the server, which removes its row and lowers the
// «Черновики: N» count under «Активные».
//
// The rows come from the real `myPosts` transport response through the
// mapper, PostsCubit and the real Conversations screen, at phone and desktop
// widths. UI copy is asserted verbatim in Russian.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';

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

Future<void> _openDrafts(WidgetTester tester) =>
    pickPostsFilter(tester, current: 'Активные', next: 'Черновики');

/// The trailing overflow button of the row showing [excerpt].
Finder _overflowOf(String excerpt) => find.descendant(
  of: postRowWith(excerpt),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Icon &&
        (w.icon == Icons.more_vert ||
            w.icon == Icons.more_horiz ||
            w.icon == Icons.more_vert_rounded ||
            w.icon == Icons.more_horiz_rounded),
  ),
);

Future<void> _openOverflow(WidgetTester tester, String excerpt) async {
  final overflow = _overflowOf(excerpt);
  expect(
    overflow,
    findsOneWidget,
    reason: 'the draft row has a trailing overflow button',
  );
  await tester.tap(overflow);
  await settlePostsTab(tester);
}

Future<void> _pickMenuItem(WidgetTester tester, String label) async {
  final item = find.descendant(of: openMenuItems, matching: find.text(label));
  expect(item, findsOneWidget, reason: 'the overflow menu offers «$label»');
  await tester.tap(item);
  await settlePostsTab(tester);
}

/// The effective colour of the first [Text] showing [text] inside [row].
Color? _textColor(WidgetTester tester, Finder row, String text) {
  final element = find
      .descendant(of: row, matching: find.text(text))
      .evaluate()
      .first;
  final widget = element.widget as Text;
  return DefaultTextStyle.of(element).style.merge(widget.style).color;
}

/// The combined opacity the row showing [excerpt] is painted with.
double _rowOpacity(WidgetTester tester, String excerpt) {
  var opacity = 1.0;
  for (final o
      in find
          .ancestor(of: find.text(excerpt), matching: find.byType(Opacity))
          .evaluate()) {
    opacity *= (o.widget as Opacity).opacity;
  }
  return opacity;
}

void main() {
  final l10n = lookupL10n(const Locale('ru'));

  for (final viewport in postsTabViewports) {
    group('Post draft rows (${viewport.name})', () {
      testWidgets(
        'a draft row is muted, labelled «Черновик», shows its text and no '
        'lifetime marker',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              // A live row's excerpt colour, for comparison.
              await pickPostsFilter(tester, current: 'Активные', next: 'Мои');
              final liveColor = _textColor(
                tester,
                postRowWith(_liveText),
                _liveText,
              );
              await pickPostsFilter(tester, current: 'Мои', next: 'Черновики');

              final row = postRowWith(_draftText);
              expect(row, findsOneWidget);
              expect(
                find.descendant(of: row, matching: find.text('Черновик')),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: row,
                  matching: find.byKey(const Key('PostConversation.Lifetime')),
                ),
                findsNothing,
                reason: 'a draft has no lifetime yet',
              );
              final draftColor = _textColor(tester, row, _draftText);
              expect(
                draftColor != liveColor || _rowOpacity(tester, _draftText) < 1,
                isTrue,
                reason:
                    'the draft text is muted: $draftColor vs live $liveColor',
              );
            },
          );
        },
      );

      testWidgets('tapping a draft row opens its saved text in the composer', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_rows()),
          body: (h) async {
            await _openDrafts(tester);
            await tester.tap(find.text(_draftText));
            await settlePostsTab(tester);

            expect(h.composerDraftIds, [_draftId]);
            expect(find.byType(PostCreateScreen), findsOneWidget);
            expect(
              tester
                  .widget<PostCreateScreen>(find.byType(PostCreateScreen))
                  .draftId,
              _draftId,
            );
            final field = find.descendant(
              of: find.byKey(PostCreateScreen.textFieldKey),
              matching: find.byType(EditableText),
            );
            expect(
              tester.widget<EditableText>(field).controller.text,
              _draftText,
            );
            expect(
              h.wire.calls('BeaconFetchById').last.variables['id'],
              _draftId,
            );
            expect(
              h.openedChats,
              isEmpty,
              reason: 'a draft has no chat to open yet',
            );
            expect(find.text('chat:$_draftId'), findsNothing);
          },
        );
      });

      testWidgets(
        'the overflow menu offers «Изменить» and «Удалить»; «Изменить» opens '
        'the composer with that draft id and its saved text',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _openDrafts(tester);
              await _openOverflow(tester, _draftText);

              expect(openMenuLabels(tester), ['Изменить', 'Удалить']);
              await _pickMenuItem(tester, 'Изменить');

              expect(h.composerDraftIds, [_draftId]);
              expect(find.byType(PostCreateScreen), findsOneWidget);
              expect(
                tester
                    .widget<PostCreateScreen>(find.byType(PostCreateScreen))
                    .draftId,
                _draftId,
              );
              final field = find.descendant(
                of: find.byKey(PostCreateScreen.textFieldKey),
                matching: find.byType(EditableText),
              );
              expect(
                tester.widget<EditableText>(field).controller.text,
                _draftText,
              );
              expect(
                h.wire.calls('BeaconFetchById').last.variables['id'],
                _draftId,
              );
              expect(h.wire.deletedIds, isEmpty);
              expect(
                h.openedChats,
                isEmpty,
                reason: 'Edit opens the composer, not the chat',
              );
            },
          );
        },
      );

      testWidgets(
        '«Удалить» asks first; cancelling keeps the draft and its row',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _openDrafts(tester);
              await _openOverflow(tester, _draftText);
              await _pickMenuItem(tester, 'Удалить');

              expect(find.text(l10n.postCreateDiscardTitle), findsOneWidget);
              expect(find.text(l10n.postCreateDiscardBody), findsOneWidget);
              expect(h.wire.deletedIds, isEmpty, reason: 'nothing yet');

              await tester.tap(
                find.descendant(
                  of: find.byType(Dialog),
                  matching: find.text(l10n.buttonCancel),
                ),
              );
              await settlePostsTab(tester);

              expect(find.text(l10n.postCreateDiscardTitle), findsNothing);
              expect(h.wire.deletedIds, isEmpty);
              expect(postRowWith(_draftText), findsOneWidget);
              expect(postRowWith(_otherDraftText), findsOneWidget);
            },
          );
        },
      );

      testWidgets(
        'confirming «Удалить» deletes the draft on the server, drops its row '
        'and lowers «Черновики: N»',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              expect(
                find.text('Черновики: 2', findRichText: true),
                findsOneWidget,
              );
              await _openDrafts(tester);
              await _openOverflow(tester, _draftText);
              await _pickMenuItem(tester, 'Удалить');

              final dialog = find.byType(Dialog);
              final confirm = find.descendant(
                of: dialog,
                matching: find.text(l10n.postCreateDiscardConfirm),
              );
              await tester.tap(
                confirm.evaluate().isNotEmpty
                    ? confirm
                    : find.descendant(
                        of: dialog,
                        matching: find.text(l10n.buttonDelete),
                      ),
              );
              await settlePostsTab(tester);

              expect(h.wire.deletedIds, [_draftId]);
              expect(find.text(_draftText), findsNothing);
              expect(postRowWith(_otherDraftText), findsOneWidget);

              await pickPostsFilter(
                tester,
                current: 'Черновики',
                next: 'Активные',
              );
              expect(
                find.text('Черновики: 1', findRichText: true),
                findsOneWidget,
              );
              expect(
                find.text('Черновики: 2', findRichText: true),
                findsNothing,
              );
            },
          );
        },
      );
    });
  }
}
