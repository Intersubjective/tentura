import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// Issue #720 (#720a, option A): one noun for a Post along the whole flow.
// The tab says «Posts», so the composer says «New post», the participants
// sheet «IN THE POST», and leaving, deleting, the read-only hint and the
// pinned «sent you» line speak of the post, never of a «chat».
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

const _postKeys = [
  'postsTabNewPost',
  'postParticipantsInConversation',
  'postMenuLeave',
  'postLeaveConfirmTitle',
  'postDeleteConfirmBody',
  'postChatReadOnlyHint',
  'postStartedByLine',
  'postStartedByLineWithNote',
];

void main() {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');

  test('the composer is «New post» / «Новый пост»', () {
    expect(L10nEn().postsTabNewPost, 'New post');
    expect(L10nRu().postsTabNewPost, 'Новый пост');
  });

  test('the participants sheet says IN THE POST / В ПОСТЕ', () {
    expect(L10nEn().postParticipantsInConversation(3), 'IN THE POST · 3');
    expect(L10nRu().postParticipantsInConversation(3), 'В ПОСТЕ · 3');
  });

  test('Post copy names the post, not a chat, in every locale', () {
    for (final key in _postKeys) {
      final e = (en[key] as String).toLowerCase();
      final r = (ru[key] as String).toLowerCase();
      expect(e, contains('post'), reason: 'en $key');
      expect(e, isNot(contains('chat')), reason: 'en $key');
      expect(r, contains('пост'), reason: 'ru $key');
      expect(r, isNot(contains('чат')), reason: 'ru $key');
    }
  });

  test('guard: the sent-you line still is not a forward', () {
    expect(en['postStartedByLine'], '{name} sent you this post');
    expect(ru['postStartedByLine'] as String, isNot(contains('переслал')));
  });
}
