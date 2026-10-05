import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

/// Request plan («либретто», #220) Activity rows.
void main() {
  final en = L10nEn();
  final ru = L10nRu();

  String payload(String eventType, {String excerpt = 'Build frame'}) =>
      jsonEncode({
        'eventType': eventType,
        'beaconId': 'B1',
        'coordinationItemId': 'PS1',
        'beaconTitle': 'Garden beds',
        'excerpt': excerpt,
      });

  const types = {
    'planStepDue': 'plan_step_due',
    'planStepTurn': 'plan_step_turn',
    'planChangePending': 'plan_change_pending',
    'planStepReminder': 'plan_step_reminder',
    'planStepOverdue': 'plan_step_overdue',
    'planStepLate': 'plan_step_late',
    'planCantMake': 'plan_cant_make',
    'planStepUnassigned': 'plan_step_unassigned',
    'planEdited': 'plan_edited',
    'planStepDone': 'plan_step_done',
  };

  test('every plan event has its own localized headline, no clock times', () {
    for (final l10n in [en, ru]) {
      final headlines = <String>{};
      for (final MapEntry(key: type, value: key) in types.entries) {
        final copy = planReceiptDisplayCopy(
          presentationKey: key,
          presentationPayloadJson: payload(type),
          l10n: l10n,
        );
        expect(copy, isNotNull, reason: type);
        expect(copy!.body, 'Build frame', reason: type);
        expect(copy.headline, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
        headlines.add(copy.headline);
      }
      expect(headlines, hasLength(types.length));
    }
  });

  test('ru copy', () {
    String h(String type) => planReceiptDisplayCopy(
      presentationKey: types[type],
      presentationPayloadJson: payload(type),
      l10n: ru,
    )!.headline;
    expect(h('planStepDue'), 'Ваш шаг начался');
    expect(h('planChangePending'), 'Ваш шаг изменён');
    expect(h('planCantMake'), 'Не успевает');
    expect(h('planStepDone'), 'Шаг выполнен');
  });

  test('presentationKey alone is enough (payload without eventType)', () {
    final copy = planReceiptDisplayCopy(
      presentationKey: 'plan_step_overdue',
      presentationPayloadJson: '{}',
      l10n: en,
    );
    expect(copy?.headline, en.planReceiptStepOverdue);
    expect(copy?.body, '');
  });

  test('non-plan events are left alone', () {
    expect(
      planReceiptDisplayCopy(
        presentationKey: 'room_message_posted',
        presentationPayloadJson: jsonEncode({'eventType': 'roomMessagePosted'}),
        l10n: en,
      ),
      isNull,
    );
    expect(
      planReceiptEventType(
        presentationKey: 'coordination_changed',
        presentationPayloadJson: '',
      ),
      isNull,
    );
  });

  test('feed row and Request-scoped row use the plan copy, not the push '
      'title', () {
    final row = resolveUpdatesFeedRowCopy(
      title: 'Ваш шаг начался',
      body: 'Garden beds — Build frame',
      presentationKey: 'plan_step_due',
      presentationPayloadJson: payload('planStepDue'),
      l10n: en,
    );
    expect(row.headline, en.planReceiptStepDue);
    expect(row.body, 'Build frame');

    final scoped = requestScopedEventCopy(
      title: 'Olga changed the plan',
      body: 'Garden beds — Build frame',
      presentationKey: 'plan_edited',
      presentationPayloadJson: payload('planEdited'),
      requestTitle: 'Garden beds',
      actorName: 'Olga',
      l10n: ru,
    );
    expect(scoped.event, ru.planReceiptEdited);
    expect(scoped.excerpt, 'Build frame');
  });
}
