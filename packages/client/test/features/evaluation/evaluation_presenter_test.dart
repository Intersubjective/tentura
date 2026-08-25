import 'package:built_collection/built_collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/data/gql/_g/evaluation_draft_save.var.gql.dart';
import 'package:tentura/features/evaluation/data/gql/_g/evaluation_submit.var.gql.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_capability_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_legacy_reason_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  test('impact presenter covers exact five values and no basis in English', () {
    expect(
      evaluationImpactValues(),
      [
        EvaluationValue.pos2,
        EvaluationValue.pos1,
        EvaluationValue.zero,
        EvaluationValue.neg1,
        EvaluationValue.neg2,
      ],
    );
    expect(
      presentEvaluationValue(EvaluationValue.pos2, en).label,
      'Helped a lot',
    );
    expect(
      presentEvaluationValue(EvaluationValue.pos1, en).label,
      'Helped somewhat',
    );
    expect(
      presentEvaluationValue(EvaluationValue.zero, en).label,
      'No real effect',
    );
    expect(
      presentEvaluationValue(EvaluationValue.neg1, en).label,
      'Hurt somewhat',
    );
    expect(
      presentEvaluationValue(EvaluationValue.neg2, en).label,
      'Hurt a lot',
    );
    expect(
      presentEvaluationValue(EvaluationValue.noBasis, en).label,
      'No basis',
    );
    expect(
      presentEvaluationValue(EvaluationValue.noBasis, en).emoji,
      '❔',
    );
    expect(presentEvaluationValue(EvaluationValue.pos2, en).emoji, '🤩');
    expect(presentEvaluationValue(EvaluationValue.pos1, en).emoji, '👍');
    expect(presentEvaluationValue(EvaluationValue.zero, en).emoji, '🤷');
    expect(presentEvaluationValue(EvaluationValue.neg1, en).emoji, '👎');
    expect(presentEvaluationValue(EvaluationValue.neg2, en).emoji, '😠');
  });

  test('impact presenter localizes Russian labels', () {
    expect(
      presentEvaluationValue(EvaluationValue.pos2, ru).label,
      'Очень помогло',
    );
    expect(
      presentEvaluationValue(EvaluationValue.pos1, ru).label,
      'Скорее помогло',
    );
    expect(
      presentEvaluationValue(EvaluationValue.zero, ru).label,
      'Без заметного эффекта',
    );
    expect(
      presentEvaluationValue(EvaluationValue.neg1, ru).label,
      'Скорее навредило',
    );
    expect(
      presentEvaluationValue(EvaluationValue.neg2, ru).label,
      'Сильно навредило',
    );
    expect(
      presentEvaluationValue(EvaluationValue.noBasis, ru).label,
      'Нет оснований',
    );
  });

  test(
    'capability presenter follows canonical order and excludes unknown slugs',
    () {
      expect(
        presentAcknowledgedCapabilities([
          'pets',
          'transport',
          'not-a-capability',
        ], en),
        'Transport, Pets',
      );
      expect(
        presentAcknowledgedCapabilities(['transport', 'pets', 'storage'], en),
        'Transport, Storage +1',
      );
    },
  );

  test(
    'legacy presenter maps every known reason slug and falls back for unknown',
    () {
      const slugs = [
        'clear_request',
        'fair_closure',
        'useful_updates',
        'coordinated_well',
        'unclear_request',
        'poor_updates',
        'closed_unfairly',
        'hard_to_coordinate',
        'delivered_as_promised',
        'very_useful',
        'communicated_honestly',
        'above_expectation',
        'did_not_follow_through',
        'overpromised',
        'created_extra_work',
        'poor_communication',
        'reached_right_person',
        'forwarded_quickly',
        'useful_routing_note',
        'crucial_bridge',
        'sent_to_wrong_people',
        'created_noise',
        'forwarded_too_late',
        'misleading_note',
      ];
      for (final slug in slugs) {
        final label = presentLegacyEvaluationReason(slug, en);
        expect(label, isNot(contains('_')), reason: slug);
        expect(label, isNot('Reason'), reason: slug);
      }
      expect(presentLegacyEvaluationReason('unknown_slug', en), 'Reason');
    },
  );

  test(
    'submit and draft-save variable serialization preserves null versus empty tags',
    () {
      final submitNull = GEvaluationSubmitVars.create(
        id: 'b',
        evaluatedUserId: 'u',
        value: 3,
      ).toJson();
      final submitEmpty = GEvaluationSubmitVars.create(
        id: 'b',
        evaluatedUserId: 'u',
      value: 3,
      reasonTags: BuiltList<String>(),
      acknowledgedHelpTags: BuiltList<String>(),
    ).toJson();
    final submitAcknowledgedNull = GEvaluationSubmitVars.create(
      id: 'b',
      evaluatedUserId: 'u',
      value: 3,
      reasonTags: BuiltList<String>(),
    ).toJson();
      final draftNull = GEvaluationDraftSaveVars.create(
        id: 'b',
        evaluatedUserId: 'u',
        value: 3,
      ).toJson();
      final draftEmpty = GEvaluationDraftSaveVars.create(
        id: 'b',
        evaluatedUserId: 'u',
        value: 3,
        reasonTags: BuiltList<String>(),
      ).toJson();
    expect(submitNull, isNot(containsPair('reasonTags', anything)));
    expect(submitNull,
        isNot(containsPair('acknowledgedHelpTags', anything)));
    expect(submitEmpty, containsPair('reasonTags', isEmpty));
    expect(submitEmpty, containsPair('acknowledgedHelpTags', isEmpty));
    expect(submitAcknowledgedNull,
        isNot(containsPair('acknowledgedHelpTags', anything)));
      expect(draftNull, isNot(containsPair('reasonTags', anything)));
      expect(draftEmpty, containsPair('reasonTags', isEmpty));
    },
  );
}
