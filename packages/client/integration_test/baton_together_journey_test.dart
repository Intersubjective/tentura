// «Who'll take it?» together journey in the real browser (baton together plan
// unit W). Public API setup (four people, one admitted room, one baton), then
// each person's visible text per step: the asked person A answers «Together
// with…» X, X joins (in RU), the author sees one pair row and chooses the
// pair, the observer reads «A and X took it.», X's Activity has the receipt.
//
// A's «Together with…» answer goes through the public mutation: the button
// itself is gated by kBatonTogetherEnabled, which stays off until ship unit V.
// The button and picker are covered by room_baton_card_candidate_together_test.
import 'dart:convert';

import 'package:ferry/ferry.dart' show OperationRequest;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart'
    show Gv2_RoomBatonCandidateInput;
import 'package:tentura/features/beacon_threads/data/gql/_g/room_baton_create.req.gql.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/room_baton_respond.req.gql.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/room_message_list.req.gql.dart';
import 'package:tentura/features/beacon_view/data/gql/_g/beacon_help_offer_accept.req.gql.dart';
import 'package:tentura/features/forward/data/gql/_g/beacon_offer_help.req.gql.dart';
import 'package:tentura/features/forward/data/gql/_g/forward_beacon.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_accept.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_create.req.gql.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/profile/data/gql/_g/profile_update.req.gql.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _anna = 'Anna';
const _boris = 'Boris';
const _kira = 'Kira';
const _vera = 'Vera';

Future<void> _openRoomAs(
  WidgetTester tester,
  String email,
  String title, {
  required String locale,
}) async {
  await logout(tester);
  await loginAs(tester, email);
  await GetIt.I<SettingsCubit>().setLocalePreference(locale);
  await pumpBounded(tester, frames: 12);
  await openRequestFromMyWork(tester, requestTitle: title);
  // The tab strip appears only after the Request detail has loaded.
  await pumpUntil(
    tester,
    () =>
        find.byKey(TestIds.key(TestIds.beaconTabRoom)).evaluate().isNotEmpty ||
        find.byKey(TestIds.key(TestIds.roomMessageInput)).evaluate().isNotEmpty,
  );
  await enterChatIfNeeded(tester);
}

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(Navigator).first))!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ask, together, join, choose the pair, room line and receipt', (
    tester,
  ) async {
    await launchApp(app.main);
    // false = do not swallow app exceptions: any error the app throws during the
    // journey surfaces as a test failure instead of being drained silently.
    e2eDrainExceptions = false;
    await pumpSettleBounded(tester);
    final people = await bootstrapWitnessFixture(
      runId: uniqueRunId('baton-together'),
    );
    final title = uniqueRequestTitle('Baton together');
    late String beaconId;
    late String batonId;

    // Every setup mutation must succeed: no `errors`, non-null `data`, so a
    // broken fixture fails here and not as a missing text in a later step.
    Future<Map<String, dynamic>> asUser(
      String email,
      OperationRequest<Object?, Object?> request,
    ) async {
      final response = await postGraphQlAsUser(
        email: email,
        restoreEmail: people.aliceEmail,
        request: request,
      );
      expect(
        response.containsKey('errors') && response['errors'] != null,
        isFalse,
        reason:
            'GraphQL errors for ${request.operation.operationName}: '
            '${response['errors']}',
      );
      expect(response['data'], isNotNull);
      return response;
    }

    await runE2eStep('set up four people, one room, one baton', () async {
      await logout(tester);
      await loginAs(tester, people.aliceEmail);
      for (final p in [
        (people.aliceEmail, people.aliceUserId, _anna),
        (people.bobEmail, people.bobUserId, _boris),
        (people.carolEmail, people.carolUserId, _kira),
        (people.eveEmail, people.eveUserId, _vera),
      ]) {
        final updated = await asUser(
          p.$1,
          GProfileUpdateReq((b) => b.vars.displayName = p.$3),
        );
        expect(((updated['data'] as Map)['userUpdate'] as Map)['id'], p.$2);
      }
      final invitation = await asUser(
        people.aliceEmail,
        GInvitationCreateReq((b) => b.vars.addresseeName = 'Bob'),
      );
      await asUser(
        people.bobEmail,
        GInvitationAcceptReq(
          (b) => b.vars.id =
              ((invitation['data'] as Map)['invitationCreate'] as Map)['id']
                  as String,
        ),
      );
      beaconId = await createPublishedBeacon(title: title);
      await forwardBeaconTo(beaconId: beaconId, recipientId: people.bobUserId);
      for (final hop in [
        (people.bobEmail, people.carolUserId),
        (people.carolEmail, people.eveUserId),
      ]) {
        await asUser(
          hop.$1,
          GForwardBeaconReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..recipientIds.add(hop.$2),
          ),
        );
      }
      for (final helper in [
        (people.bobEmail, people.bobUserId),
        (people.carolEmail, people.carolUserId),
        (people.eveEmail, people.eveUserId),
      ]) {
        await asUser(
          helper.$1,
          GBeaconOfferHelpReq((b) => b.vars.beaconId = beaconId),
        );
        await asUser(
          people.aliceEmail,
          GAcceptHelpOfferReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..offerUserId = helper.$2,
          ),
        );
      }
      final created = await asUser(
        people.aliceEmail,
        GRoomBatonCreateReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..text = 'Who can take the delivery?'
            ..candidates.replace([
              Gv2_RoomBatonCandidateInput(
                (i) => i
                  ..userId = people.bobUserId
                  ..tier = 1,
              ),
            ]),
        ),
      );
      // roomBatonCreate returns the message id; answers need the baton id,
      // which the room list carries in the baton payload.
      final messageId = (created['data'] as Map)['roomBatonCreate'] as String;
      final list = await asUser(
        people.bobEmail,
        GRoomMessageListReq((b) => b.vars.beaconId = beaconId),
      );
      final row = ((list['data'] as Map)['RoomMessageList'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((m) => m['id'] == messageId);
      batonId =
          (jsonDecode(row['batonDataJson'] as String)
                  as Map<String, dynamic>)['id']
              as String;
      // A answers «Together with…» X.
      await asUser(
        people.bobEmail,
        GRoomBatonRespondReq(
          (b) => b.vars
            ..batonId = batonId
            ..canHelp = true
            ..partnerUserId = people.carolUserId,
        ),
      );
    });

    await runE2eStep('A sees the pending together answer (EN)', () async {
      await _openRoomAs(tester, people.bobEmail, title, locale: 'en');
      final l10n = _l10n(tester);
      expect(l10n.localeName, 'en');
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonTogetherPending(_kira)),
        label: 'A pending together answer naming X',
      );
    });

    await runE2eStep('X joins (RU)', () async {
      await _openRoomAs(tester, people.carolEmail, title, locale: 'ru');
      final l10n = _l10n(tester);
      expect(l10n.localeName, 'ru');
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonPartnerPrompt(_boris)),
        label: 'RU partner prompt naming A',
      );
      expect(find.text(l10n.batonPartnerNote), findsOneWidget);
      expect(find.text(l10n.batonPartnerJoin), findsOneWidget);
      expect(find.text(l10n.batonPartnerCant), findsOneWidget);
      // The partner card never discloses tiers or other candidates.
      final card = find.byType(RoomBatonCard);
      expect(card, findsOneWidget);
      for (final leak in [
        l10n.batonTierLabel(1),
        _anna,
        _vera,
        _kira,
      ]) {
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining(leak, findRichText: true),
          ),
          findsNothing,
          reason: '«$leak» must not appear on the partner card',
        );
      }
      await tapAndSettle(tester, find.text(l10n.batonPartnerJoin));
      await pumpBounded(tester, frames: 5);
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonPartnerJoined(_boris)),
        label: 'RU joined state',
      );

      expect(find.text(l10n.batonPartnerJoin), findsNothing);
    });

    await runE2eStep('author sees one pair row and chooses the pair', () async {
      await _openRoomAs(tester, people.aliceEmail, title, locale: 'en');
      final l10n = _l10n(tester);
      final pair = l10n.batonPairNames(_boris, _kira);
      await pumpUntilVisible(
        tester,
        find.text(pair),
        label: 'one pair row on the author card',
      );
      expect(find.text(pair), findsOneWidget);
      expect(find.text(l10n.batonStatusCanHelpTogether), findsOneWidget);
      final choose = find.text(l10n.batonChooseNow);
      await tester.ensureVisible(choose);
      await tapAndSettle(tester, choose);
      final sheetRow = find.descendant(
        of: find.byType(ListTile),
        matching: find.text(pair),
      );
      await pumpUntilVisible(tester, sheetRow, label: 'pair in choose sheet');
      expect(sheetRow, findsOneWidget);
      expect(find.text(l10n.batonChoosePairHint), findsOneWidget);
      await tapAndSettle(tester, sheetRow);
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonPlanStepPromptBodyPair(_kira)),
        label: 'plan-step prompt names the partner',
      );
      await tapAndSettle(tester, find.text(l10n.batonPlanStepNotNow));
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonTookItPair(_boris, _kira)),
        label: 'author sees the pair took it',
      );
    });

    await runE2eStep('observer reads «A and X took it.»', () async {
      await _openRoomAs(tester, people.eveEmail, title, locale: 'en');
      final l10n = _l10n(tester);
      await pumpUntilVisible(
        tester,
        find.text(l10n.batonTookItPair(_boris, _kira)),
        label: 'observer pair line',
      );
    });

    await runE2eStep('X Activity has the receipt (RU)', () async {
      await logout(tester);
      await loginAs(tester, people.carolEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference('ru');
      try {
        await pumpBounded(tester, frames: 12);
        await goToPath(tester, kPathMyWork);
        await GetIt.I<AttentionCase>().refresh();
        final l10n = _l10n(tester);
        expect(l10n.localeName, 'ru');
        final receipt = find.descendant(
          of: find.byType(AttentionMiniCard),
          matching: find.textContaining(
            'Вы и $_boris взялись',
            findRichText: true,
          ),
        );
        await pumpUntilVisible(
          tester,
          receipt,
          label: 'taken-together receipt',
        );
      } finally {
        await GetIt.I<SettingsCubit>().setLocalePreference('en');
      }
    });
  });
}
