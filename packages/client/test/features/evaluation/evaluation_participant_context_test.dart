import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_participant_context.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  const en = Locale('en');
  const ru = Locale('ru');
  final enL10n = lookupL10n(en);
  final ruL10n = lookupL10n(ru);

  final committedAt = DateTime.utc(2026, 3, 14, 12);

  EvaluationParticipant participantOf({
    EvaluationParticipantRole role = EvaluationParticipantRole.committer,
    DateTime? committedAt,
    String? forwarderDisplayName,
    bool isOptional = false,
    String offerMessage = '',
  }) => EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: role,
    committedAt: committedAt,
    forwarderDisplayName: forwarderDisplayName,
    isOptional: isOptional,
    offerMessage: offerMessage,
  );

  test('a forwarder is described as a forwarder in both locales', () {
    final participant = participantOf(
      role: EvaluationParticipantRole.forwarder,
      committedAt: committedAt,
      forwarderDisplayName: 'Bob',
    );
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participant,
      ).line,
      'Forwarded the request',
    );
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).line,
      'Передал(а) запрос дальше',
    );
  });

  test('a committed helper with a forwarder names both in both locales', () {
    final participant = participantOf(
      committedAt: committedAt,
      forwarderDisplayName: 'Bob',
    );
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participant,
      ).line,
      contains('via Bob'),
    );
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).line,
      contains('через Bob'),
    );
  });

  test('a committed helper without a forwarder shows only the date', () {
    final participant = participantOf(committedAt: committedAt);
    final line = presentParticipantContext(
      l10n: enL10n,
      locale: en,
      participant: participant,
    ).line;
    expect(line, startsWith('Helping since '));
    expect(line, isNot(contains('·')));
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).line,
      startsWith('Помогал(а) с '),
    );
  });

  test('a row with no commit date falls back to localized copy', () {
    final participant = participantOf();
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participant,
      ).line,
      'Helped with this request',
    );
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).line,
      'Помогал(а) с этим запросом',
    );
  });

  test('an optional target gets the ended line in both locales', () {
    final participant = participantOf(
      role: EvaluationParticipantRole.formerCommitter,
      committedAt: committedAt,
      isOptional: true,
    );
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participant,
      ).endedLine,
      'Participation ended',
    );
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).endedLine,
      'Участие завершилось',
    );
  });

  test('a still-active target has no ended line', () {
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participantOf(committedAt: committedAt),
      ).endedLine,
      isNull,
    );
  });

  test('an offer message is quoted in both locales', () {
    final participant = participantOf(offerMessage: 'I can drive');
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participant,
      ).offerLine,
      '“I can drive”',
    );
    expect(
      presentParticipantContext(
        l10n: ruL10n,
        locale: ru,
        participant: participant,
      ).offerLine,
      '«I can drive»',
    );
  });

  test('an empty offer message yields no offer line', () {
    expect(
      presentParticipantContext(
        l10n: enL10n,
        locale: en,
        participant: participantOf(),
      ).offerLine,
      isNull,
    );
  });

  test('the date is formatted for the locale, never a server string', () {
    final participant = participantOf(committedAt: committedAt);
    final enLine = presentParticipantContext(
      l10n: enL10n,
      locale: en,
      participant: participant,
    ).line;
    final ruLine = presentParticipantContext(
      l10n: ruL10n,
      locale: ru,
      participant: participant,
    ).line;
    expect(enLine, isNot(contains('2026-03-14')));
    expect(enLine, contains('2026'));
    expect(ruLine, contains('2026'));
    expect(enLine, isNot(equals(ruLine)));
  });
}
