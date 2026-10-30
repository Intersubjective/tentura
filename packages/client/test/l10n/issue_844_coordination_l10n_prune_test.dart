// Issue #844 / W10 batch 1: unused coordination* ARB keys removed from EN+RU.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

const _locales = ['en', 'ru'];

/// Keys confirmed unused in lib/, test/, integration_test/, tool/, scripts/.
const _removedKeys = [
  'coordinationResponseRoomAdmits',
  'coordinationResponseRoomNoAdmission',
  'coordinationInviteToRoomRow',
  'coordinationSetOverallStatus',
  'coordinationCreatePromiseSheetPrompt',
  'coordinationCreatePromiseFromMessage',
  'coordinationPromiseTargetPickerLabel',
  'coordinationCreatePromiseNoTargets',
  'coordinationDeleteDraftTitle',
  'coordinationDeleteDraftBody',
  'coordinationAskFromMessagePreview',
  'coordinationComposerNoTargetWillSaveDraft',
  'coordinationComposerSaveDraft',
  'coordinationComposerTargetGuidance',
  'coordinationPublishAsk',
  'coordinationPublishPromise',
  'coordinationPublishBlocker',
  'coordinationComposerTargetNone',
  'coordinationStalenessLabel',
  'coordinationStaleness1Day',
  'coordinationStaleness3Days',
  'coordinationStaleness1Week',
  'coordinationStaleness2Weeks',
  'coordinationStalenessNoDeadline',
  'coordinationStalenessDefaultHint',
  'coordinationBlockerActionResolve',
  'coordinationBlockerActionCancel',
  'coordinationBlockerActionDiscuss',
  'coordinationItemDiscussionComposerHint',
  'coordinationMarkBlockerTitle',
  'coordinationMarkBlockerHint',
  'coordinationPromoteTitleHint',
  'coordinationPromoteBodyHint',
  'coordinationAskAcceptLabel',
  'coordinationPromiseAcceptLabel',
  'coordinationMarkAskTitle',
  'coordinationMarkAskHint',
];

void main() {
  test('W10 batch 1 coordination* keys are gone from every ARB', () {
    expect(_removedKeys, hasLength(37));
    for (final locale in _locales) {
      final arb = _arb(locale);
      for (final key in _removedKeys) {
        expect(arb.containsKey(key), isFalse, reason: 'app_$locale.arb: $key');
        expect(
          arb.containsKey('@$key'),
          isFalse,
          reason: 'app_$locale.arb: @$key',
        );
      }
    }
  });
}
