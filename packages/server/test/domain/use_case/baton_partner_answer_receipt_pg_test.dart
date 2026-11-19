@Tags(['pg'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

import '../../support/baton_receipt_fixture.dart';
import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BATON_RECEIPT_TEST_DB',
    defaultNamePrefix: 'tentura_test_baton_receipt',
  );
  final skipReason = await pgSkipReason(target);
  final fixture = BatonReceiptFixture(target);

  group('The inviter reads their partner’s answer in Updates', () {
    setUpAll(fixture.open);
    tearDownAll(fixture.close);

    Future<Map<String, dynamic>> readAnswer(String beaconId) async {
      final data =
          await fixture.schema.parseAndExecute(
                r'''
        query PartnerAnswer($beaconId: String!) {
          attentionRequestHistory(beaconId: $beaconId) {
            items { id actorUserId presentationKey presentationPayloadJson }
          }
        }
        ''',
                variableValues: {'beaconId': beaconId},
                globalVariables: {
                  kGlobalInputQueryJwt: const JwtEntity(sub: batonBoris),
                },
              )
              as Map;
      final items = (data['attentionRequestHistory'] as Map)['items'] as List;
      return items.cast<Map<String, dynamic>>().singleWhere(
        (item) => item['presentationKey'] == 'baton_partner_answered',
      );
    }

    for (final (label, request, accepted) in [
      ('joining stays accepted', batonJoinedRequest, true),
      ('declining stays declined', batonDeclinedRequest, false),
    ]) {
      test('$label before and after notification dispatch', () async {
        final baton = await fixture.propose(request);
        await fixture.answer(baton, accept: accepted);
        final immediate = await readAnswer(request);

        await fixture.drainChannels();
        final refreshed = await readAnswer(request);

        expect(immediate['actorUserId'], batonCarol);
        expect(refreshed['id'], immediate['id']);
        final immediatePayload =
            jsonDecode(immediate['presentationPayloadJson'] as String) as Map;
        final refreshedPayload =
            jsonDecode(refreshed['presentationPayloadJson'] as String) as Map;
        expect(
          (immediatePayload['accepted'], refreshedPayload['accepted']),
          (accepted, accepted),
          reason:
              'The GraphQL receipt must explicitly preserve the answer in both reads',
        );
      });
    }
  }, skip: skipReason);
}
