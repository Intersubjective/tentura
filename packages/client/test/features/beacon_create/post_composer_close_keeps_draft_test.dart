// Composer leave choices are observed on the Posts tab, over the same HTTP
// server that accepted the draft writes. No test inserts a draft into the
// Posts cubit or manufactures a domain entity after closing the composer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../inbox/posts_tab_wire_test_support.dart';

const _typed = 'Черновик поста про велосипед';
const _remaining = 'Книги для обмена';

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().toUtc();
  return [
    myPostsWireRow(
      id: 'Blivepost001',
      excerpt: 'Опубликованный пост',
      lastActivityAt: now,
      expiresAt: now.add(const Duration(hours: 20)),
    ),
    myPostsWireRow(
      id: 'Botherdraft01',
      excerpt: _remaining,
      isAuthor: true,
      status: 3,
      lastActivityAt: now.subtract(const Duration(hours: 1)),
    ),
  ];
}

Finder get _textField => find.byKey(PostCreateScreen.textFieldKey);
Finder get _closeControl => find.descendant(
  of: find.byType(TenturaTopBar),
  matching: find.byIcon(Icons.close),
);
Finder _dialogButton(String label) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(label));

Future<void> _typeAndClose(WidgetTester tester, PostsTabHarness h) async {
  // Push the real destination without waiting for it to pop.
  unawaited(h.openComposer(''));
  await settlePostsTab(tester);
  await tester.enterText(_textField, _typed);
  // Ferry uses real async in this harness, including the 1.5 s autosave.
  await Future<void>.delayed(const Duration(milliseconds: 1700));
  await settlePostsTab(tester);
  expect(h.wire.calls('BeaconCreate'), hasLength(1));
  expect(h.wire.calls('BeaconCreate').single.variables['kind'], 1);
  expect(h.wire.calls('BeaconCreate').single.variables['draft'], isTrue);
  expect(h.wire.calls('PostUpdateDraft'), isNotEmpty);
  await tester.tap(_closeControl);
  await settlePostsTab(tester);
}

Finder _draftRow(String id, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) => widget is PostConversationRow && widget.post.id == id,
      skipOffstage: skipOffstage,
    );

/// Start with an empty Drafts view, compose a new Post, and observe its saved
/// text in the real Posts row while the composer covers that view. The row is
/// populated by a fresh MyPosts response after the autosave, not by the test.
Future<String> _composeFirstListedDraft(
  WidgetTester tester,
  PostsTabHarness h,
) async {
  expect(h.wire.rows.where((row) => row['status'] == 3), isEmpty);
  expect(find.textContaining('Черновики:'), findsNothing);
  await pickPostsFilter(tester, current: 'Активные', next: 'Черновики');
  expect(postsEmptyState, findsOneWidget);
  expect(find.byType(PostConversationRow), findsNothing);

  await _typeAndClose(tester, h);
  final saved = h.wire.rows.where((row) => row['status'] == 3).toList();
  expect(
    saved,
    hasLength(1),
    reason: 'the composer created the first server draft',
  );
  expect(saved.single['rootExcerpt'], _typed);
  final id = saved.single['id'] as String;
  expect(h.wire.calls('MyPosts').length, greaterThan(1));
  final row = _draftRow(id, skipOffstage: false);
  expect(
    row,
    findsOneWidget,
    reason: 'the newly typed draft already reached the Posts view',
  );
  expect(
    find.descendant(
      of: row,
      matching: find.text(_typed, skipOffstage: false),
      skipOffstage: false,
    ),
    findsOneWidget,
  );
  return id;
}

void main() {
  final l10n = lookupL10n(const Locale('ru'));
  for (final viewport in postsTabViewports) {
    group('Leaving a Post composer (${viewport.name})', () {
      testWidgets('typed content offers Keep draft and Discard', (
        tester,
      ) async {
        await withPostsTab(
          tester,
          size: viewport.size,
          wire: PostsTabWire(_rows()),
          body: (h) async {
            await _typeAndClose(tester, h);
            expect(find.text(l10n.beaconCreateLeaveTitle), findsOneWidget);
            expect(find.text(l10n.beaconCreateLeaveBody), findsOneWidget);
            expect(
              _dialogButton(l10n.beaconCreateLeaveKeepDraft),
              findsOneWidget,
            );
            expect(
              _dialogButton(l10n.beaconCreateLeaveDiscard),
              findsOneWidget,
            );
            expect(find.text(l10n.postCreateDiscardTitle), findsNothing);
          },
        );
      });

      testWidgets(
        'Keep draft closes the composer and lists its saved text under Posts drafts',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _typeAndClose(tester, h);
              expect(
                _dialogButton(l10n.beaconCreateLeaveKeepDraft),
                findsOneWidget,
              );
              await tester.tap(_dialogButton(l10n.beaconCreateLeaveKeepDraft));
              await settlePostsTab(tester);
              expect(find.byType(PostCreateScreen), findsNothing);
              expect(h.wire.deletedIds, isEmpty);
              expect(h.wire.calls('PostPublish'), isEmpty);
              expect(
                find.text('Черновики: 2', findRichText: true),
                findsOneWidget,
              );
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );
              expect(postRowWith(_typed), findsOneWidget);
              expect(postRowWith(_remaining), findsOneWidget);
              expect(
                h.wire.calls('MyPosts').length,
                greaterThan(1),
              );
            },
          );
        },
      );

      testWidgets(
        'Discard closes the composer and removes its draft from Posts and the draft count',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _typeAndClose(tester, h);
              final readsBeforeLeaving = h.wire.calls('MyPosts').length;
              expect(
                _dialogButton(l10n.beaconCreateLeaveDiscard),
                findsOneWidget,
              );
              await tester.tap(_dialogButton(l10n.beaconCreateLeaveDiscard));
              await settlePostsTab(tester);
              expect(find.byType(PostCreateScreen), findsNothing);
              expect(h.wire.deletedIds, ['Bcreatedpost01']);
              expect(
                h.wire.calls('MyPosts').length,
                greaterThan(readsBeforeLeaving),
              );
              expect(h.wire.calls('PostPublish'), isEmpty);
              expect(
                find.text('Черновики: 1', findRichText: true),
                findsOneWidget,
              );
              expect(
                find.text('Черновики: 2', findRichText: true),
                findsNothing,
              );
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );
              expect(postRowWith(_remaining), findsOneWidget);
              expect(postRowWith(_typed), findsNothing);
            },
          );
        },
      );

      testWidgets(
        'Keep draft preserves the first newly composed Post in Drafts and reopens its saved text',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(
              _rows().where((row) => row['status'] != 3).toList(),
            ),
            body: (h) async {
              final id = await _composeFirstListedDraft(tester, h);
              expect(
                _dialogButton(l10n.beaconCreateLeaveKeepDraft),
                findsOneWidget,
              );
              await tester.tap(_dialogButton(l10n.beaconCreateLeaveKeepDraft));
              await settlePostsTab(tester);

              expect(find.byType(PostCreateScreen), findsNothing);
              expect(_draftRow(id), findsOneWidget);
              expect(postRowWith(_typed), findsOneWidget);
              expect(find.byType(PostConversationRow), findsOneWidget);
              expect(postsEmptyState, findsNothing);
              expect(h.wire.deletedIds, isEmpty);
              expect(h.wire.calls('PostPublish'), isEmpty);
              await pickPostsFilter(
                tester,
                current: 'Черновики',
                next: 'Активные',
              );
              expect(
                find.text('Черновики: 1', findRichText: true),
                findsOneWidget,
              );
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );

              await tester.tap(find.text(_typed));
              await settlePostsTab(tester);
              expect(find.byType(PostCreateScreen), findsOneWidget);
              expect(
                tester
                    .widget<PostCreateScreen>(find.byType(PostCreateScreen))
                    .draftId,
                id,
              );
              final field = find.descendant(
                of: _textField,
                matching: find.byType(EditableText),
              );
              expect(
                tester.widget<EditableText>(field).controller.text,
                _typed,
              );
              expect(h.wire.calls('BeaconFetchById').last.variables['id'], id);
            },
          );
        },
      );

      testWidgets(
        'Discard removes the first newly composed Post from Drafts and clears the drafts entry point',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(
              _rows().where((row) => row['status'] != 3).toList(),
            ),
            body: (h) async {
              final id = await _composeFirstListedDraft(tester, h);
              final readsBeforeDiscard = h.wire.calls('MyPosts').length;
              expect(
                _dialogButton(l10n.beaconCreateLeaveDiscard),
                findsOneWidget,
              );
              await tester.tap(_dialogButton(l10n.beaconCreateLeaveDiscard));
              await settlePostsTab(tester);

              expect(find.byType(PostCreateScreen), findsNothing);
              expect(h.wire.deletedIds, [id]);
              expect(
                h.wire.calls('MyPosts').length,
                greaterThan(readsBeforeDiscard),
              );
              expect(_draftRow(id), findsNothing);
              expect(find.text(_typed), findsNothing);
              expect(find.byType(PostConversationRow), findsNothing);
              expect(postsEmptyState, findsOneWidget);
              expect(h.wire.calls('PostPublish'), isEmpty);
              await pickPostsFilter(
                tester,
                current: 'Черновики',
                next: 'Активные',
              );
              expect(find.textContaining('Черновики:'), findsNothing);
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );
              expect(_draftRow(id), findsNothing);
              expect(postsEmptyState, findsOneWidget);
            },
          );
        },
      );

      testWidgets(
        'dismissing the leave question keeps the composer open with its text',
        (tester) async {
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire(_rows()),
            body: (h) async {
              await _typeAndClose(tester, h);
              expect(find.text(l10n.beaconCreateLeaveTitle), findsOneWidget);
              await tester.tapAt(const Offset(4, 4));
              await settlePostsTab(tester);
              expect(find.text(l10n.beaconCreateLeaveTitle), findsNothing);
              expect(find.byType(PostCreateScreen), findsOneWidget);
              final field = find.descendant(
                of: _textField,
                matching: find.byType(EditableText),
              );
              expect(
                tester.widget<EditableText>(field).controller.text,
                _typed,
              );
              expect(h.wire.deletedIds, isEmpty);
            },
          );
        },
      );
    });
  }
}
