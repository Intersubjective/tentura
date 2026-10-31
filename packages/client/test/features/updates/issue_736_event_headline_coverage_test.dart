import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #736 (returned four times; ichorid's 2026-10-31 diagnosis): the server
// often titles a receipt with the actor's name only, and the Updates row
// kept a non-canned title as its headline, so a forward read «Q1031 Alice»
// and nothing else. Every headline now comes from the event (presentation
// key + payload); the title is data.
//
// The keys are read from the server's own `_presentationKey` switch, so a
// key added there without a client line fails here.

const _policyRel = 'server/lib/domain/attention/attention_policy.dart';

/// The server file, found from wherever `flutter test` runs (the client
/// package, the repo root, or a parent of either).
File _policyFile() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    for (final candidate in [
      File('${dir.path}/../$_policyRel'),
      File('${dir.path}/packages/$_policyRel'),
    ]) {
      if (candidate.existsSync()) return candidate;
    }
    dir = dir.parent;
  }
  throw StateError('cannot find $_policyRel from ${Directory.current.path}');
}

/// (eventType, presentationKey) for every arm of the server's switch,
/// role variants included.
List<(String, String)> _serverKeys() {
  final source = _policyFile().readAsStringSync();
  final start = source.indexOf('String _presentationKey(');
  if (start < 0) throw StateError('server switch moved: $_policyRel');
  final body = source.substring(start, source.indexOf('};', start));
  final pairs = <(String, String)>[];
  for (final arm in body.split('AttentionEventType.').skip(1)) {
    final type = RegExp(r'^(\w+)').firstMatch(arm)!.group(1)!;
    for (final m in RegExp("'([a-z_]+)'").allMatches(arm)) {
      pairs.add((type, m.group(1)!));
    }
  }
  return pairs;
}

/// What each key's row says when the server title is the bare name «Bob».
const _expectedEn = {
  'author_invite_accepted': 'Bob accepted your invite',
  'author_invite_declined': "Bob can't make it",
  'author_invite_received': 'Bob asks you to help',
  'baton_all_answered': "Everyone answered your «Who'll take it?»",
  'baton_asked': 'Bob asks if you can help',
  'baton_taken': 'You took it: Bring gloves',
  'beacon_hierarchy_status_changed': 'Linked request status changed',
  'blocker_opened': 'Blocker opened',
  'blocker_resolved': 'Blocker resolved',
  'closure_cancelled': 'Evaluation cancelled',
  'closure_draft_reminder': 'Finish your review',
  'closure_finalized': 'Request closed',
  'closure_opened': 'Time to sum up',
  'closure_opened_bookmark_only': 'Time to sum up',
  'commitment_accepted': 'Commitment accepted',
  'commitment_cancelled': 'Commitment cancelled',
  'commitment_redirected': 'Reassigned to you',
  'commitment_released': 'Participation ended',
  'commitment_resolved': 'Commitment resolved',
  'coordination_changed': 'Plan updated',
  'deadline_changed': 'Deadline changed',
  'deadline_reminder': 'Deadline reminder',
  'forward_declined': "Bob can't help",
  'help_offer_submitted': 'Bob offered help',
  'help_withdrawn': 'Bob withdrew their help offer',
  'invite_accepted': 'Bob accepted your invite',
  'mutual_connection_formed': 'You and Bob are now connected',
  'needs_me': 'Asked of you',
  'obligation_ended': 'Final check ended',
  'offer_accepted': 'Bob accepted your offer',
  'offer_declined': 'Offer declined',
  'offer_removed': 'Removed from the discussion',
  'plan_cant_make': "Can't make it",
  'plan_change_pending': 'Your step changed',
  'plan_edited': 'Changed the plan',
  'plan_step_done': 'Step done',
  'plan_step_due': 'Your step has started',
  'plan_step_late': 'A step is running late',
  'plan_step_overdue': 'Your step is overdue',
  'plan_step_reminder': 'Your step starts soon',
  'plan_step_turn': 'Your turn: the previous step is done',
  'plan_step_unassigned': 'A step has no assignee',
  'post_expiring_soon': 'Your post is about to expire',
  'post_first_response': 'Bob replied to your post',
  'promise_made': 'New promise',
  'promise_withdrawn': 'Promise withdrawn',
  'relay_received': 'Bob forwarded a request to you',
  'request_stale': 'Your request has gone quiet',
  'request_status_changed': 'Request status changed',
  'room_message_posted': 'Bob wrote to you',
  'stale_reminder': 'Still needs attention',
};

const _expectedRu = {
  'author_invite_accepted': 'Bob принял(а) приглашение',
  'author_invite_declined': 'Bob не сможет',
  'author_invite_received': 'Bob зовёт вас помочь',
  'baton_all_answered': 'Все ответили на ваше «Кто возьмётся?»',
  'baton_asked': 'Bob спрашивает, сможете ли вы помочь',
  'baton_taken': 'Вы взялись: Bring gloves',
  'beacon_hierarchy_status_changed': 'Статус связанного запроса изменился',
  'blocker_opened': 'Открыт блокер',
  'blocker_resolved': 'Блокер закрыт',
  'closure_cancelled': 'Оценка отменена',
  'closure_draft_reminder': 'Завершите свою оценку',
  'closure_finalized': 'Запрос закрыт',
  'closure_opened': 'Пора подвести итоги',
  'closure_opened_bookmark_only': 'Пора подвести итоги',
  'commitment_accepted': 'Обязательство принято',
  'commitment_cancelled': 'Обязательство отменено',
  'commitment_redirected': 'Переназначено на вас',
  'commitment_released': 'Участие завершено',
  'commitment_resolved': 'Обязательство закрыто',
  'coordination_changed': 'План обновлён',
  'deadline_changed': 'Срок изменён',
  'deadline_reminder': 'Напоминание о сроке',
  'forward_declined': 'Bob не может помочь',
  'help_offer_submitted': 'Bob предложил(а) помощь',
  'help_withdrawn': 'Bob: предложение помощи отозвано',
  'invite_accepted': 'Bob принял(а) приглашение',
  'mutual_connection_formed': 'Вы и Bob теперь на связи',
  'needs_me': 'Просьба к вам',
  'obligation_ended': 'Подведение итогов закончилось',
  'offer_accepted': 'Bob принял(а) ваше предложение',
  'offer_declined': 'Предложение отклонено',
  'offer_removed': 'Удаление из обсуждения',
  'plan_cant_make': 'Не успевает',
  'plan_change_pending': 'Ваш шаг изменён',
  'plan_edited': 'Правка плана',
  'plan_step_done': 'Шаг выполнен',
  'plan_step_due': 'Ваш шаг начался',
  'plan_step_late': 'Шаг опаздывает',
  'plan_step_overdue': 'Ваш шаг просрочен',
  'plan_step_reminder': 'Скоро начнётся ваш шаг',
  'plan_step_turn': 'Ваш ход: предыдущий шаг выполнен',
  'plan_step_unassigned': 'У шага нет исполнителя',
  'post_expiring_soon': 'Пост скоро истечёт',
  'post_first_response': 'Bob ответил(а) на ваш пост',
  'promise_made': 'Новое обещание',
  'promise_withdrawn': 'Обещание отозвано',
  'relay_received': 'Bob переслал(а) вам запрос',
  'request_stale': 'В вашем запросе стало тихо',
  'request_status_changed': 'Статус запроса изменился',
  'room_message_posted': 'Bob написал(а) вам',
  'stale_reminder': 'Всё ещё ждёт внимания',
};

UpdatesFeedRowCopy _row(L10n l10n, String eventType, String key) =>
    resolveUpdatesFeedRowCopy(
      title: 'Bob',
      body: '',
      presentationKey: key,
      presentationPayloadJson: jsonEncode({
        'eventType': eventType,
        'personal': true,
        'actorUserId': 'u-bob',
        'beaconId': 'B1',
        'beaconTitle': 'Garden cleanup',
        'excerpt': 'Bring gloves',
      }),
      l10n: l10n,
    );

void main() {
  final en = L10nEn();
  final ru = L10nRu();
  late final keys = _serverKeys();

  test('the server switch was read (guard)', () {
    expect(keys.length, greaterThanOrEqualTo(50));
    expect(keys.map((k) => k.$2), contains('closure_opened_bookmark_only'));
  });

  test('every server key has an expected line (coverage map)', () {
    for (final (_, key) in keys) {
      expect(_expectedEn.keys, contains(key), reason: key);
      expect(_expectedRu.keys, contains(key), reason: key);
    }
  });

  for (final (l10n, expected) in <(L10n, Map<String, String>)>[
    (en, _expectedEn),
    (ru, _expectedRu),
  ]) {
    test('${l10n.localeName}: a bare-name title never is the headline; '
        'each key reads as its event', () {
      for (final (type, key) in keys) {
        final copy = _row(l10n, type, key);
        expect(copy.headline, expected[key], reason: key);
        expect(copy.headline, isNot('Bob'), reason: key);
      }
    });

    test('${l10n.localeName}: an unknown key reads as a generic event', () {
      final copy = resolveUpdatesFeedRowCopy(
        title: 'Bob',
        body: '',
        presentationKey: 'some_future_key',
        presentationPayloadJson: '{"eventType":"someFutureKey"}',
        l10n: l10n,
      );
      expect(copy.headline, l10n.updatesFallbackTitleGeneric);
    });

    test('${l10n.localeName}: a Questions message names the event, not '
        'just the asker', () {
      final copy = resolveUpdatesFeedRowCopy(
        title: 'Bob',
        body: '',
        presentationKey: 'room_message_posted',
        presentationPayloadJson:
            '{"eventType":"roomMessagePosted","coordinationItemId":"Q1"}',
        l10n: l10n,
      );
      expect(copy.headline, l10n.updatesQuestionsMessageFrom('Bob'));
    });
  }

  test('literal lines for the forward (guard on the wording)', () {
    expect(_expectedEn['relay_received'], 'Bob forwarded a request to you');
    expect(_expectedRu['relay_received'], 'Bob переслал(а) вам запрос');
  });
}
