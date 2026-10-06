@Tags(['pg'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/closure_receipts_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

import '../../../support/attention_payload_expectations.dart';
import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _authorId = 'Uclosurepresentation001';
const _beaconId = 'Bclosurepresentation001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_PRESENTATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_present',
  );
  final skipReason = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb database;
  late AttentionRepository receipts;
  late ClosureReceiptsRepository closureWriter;
  late MutatingUnitOfWork unitOfWork;

  group(
    'Attention queries return receipts written by the closure repository',
    () {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        database = openDisposablePgDatabase(target);
        receipts = AttentionRepository(database);
        closureWriter = ClosureReceiptsRepository(database);
        unitOfWork = MutatingUnitOfWork(database);
      });

      tearDownAll(() async {
        await database.close();
        await tearDownDisposablePgWriter(session: session);
      });

      setUp(() async {
        await session.writer.execute('''
        TRUNCATE public.notification_outbox, public.beacon, public."user" CASCADE
      ''');
        await session.writer.execute('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES ('$_authorId', 'Closure author',
          '${pgTestPublicKey('closurepresentation', 1)}')
      ''');
        await session.writer.execute('''
        INSERT INTO public.beacon (id, user_id, title, description, status)
        VALUES ('$_beaconId', '$_authorId', 'Garden cleanup', 'Help tidy the garden',
          ${BeaconStatus.reviewOpen.smallintValue})
      ''');
        await session.writer.execute('''
        INSERT INTO public.beacon_closure
          (beacon_id, epoch, status, opened_at, closes_at)
        VALUES ('$_beaconId', 2, 0, now(), now() + interval '6 days')
      ''');
        await session.writer.execute('''
        INSERT INTO public.beacon_closure_member
          (beacon_id, epoch, user_id, active_at_open)
        VALUES ('$_beaconId', 2, '$_authorId', true)
      ''');
        await session.writer.execute('''
        INSERT INTO public.beacon_closure_result
          (beacon_id, epoch, user_id, outcome, band, draft_flag, helped)
        VALUES ('$_beaconId', 2, '$_authorId', 1, 3, 0, 0.5)
      ''');
      });

      for (final eventType in ['closureOpened', 'closureFinalized']) {
        Future<AttentionReceipt> writeAndReadReceipt() async {
          await unitOfWork.run<void>(
            actorUserId: _authorId,
            action: () => eventType == 'closureOpened'
                ? closureWriter.opened(_beaconId, 2)
                : closureWriter.finalized(_beaconId, 2),
          );
          // Keep a legacy persisted payload even if a later writer stops emitting
          // numeric metadata. Existing receipts still need to remain readable.
          final legacyPayload = <String, Object?>{
            'eventType': eventType,
            'beaconId': _beaconId,
            'epoch': 2,
            if (eventType == 'closureFinalized') ...{
              'outcome': 1,
              'band': 3,
              'draftFlag': 0,
            },
          };
          await database.customStatement(
            r'''
              UPDATE public.notification_outbox
              SET presentation_payload = $1::jsonb
              WHERE account_id = $2 AND beacon_id = $3''',
            [jsonEncode(legacyPayload), _authorId, _beaconId],
          );
          final storedRows = await session.writer.execute('''
          SELECT presentation_payload::text FROM public.notification_outbox
          WHERE account_id = '$_authorId' AND beacon_id = '$_beaconId'
        ''');
          expect(storedRows, hasLength(1));
          final stored =
              jsonDecode(storedRows.single.single! as String)
                  as Map<String, dynamic>;
          expect(stored, legacyPayload);
          for (final key in [
            'epoch',
            if (eventType == 'closureFinalized') ...[
              'outcome',
              'band',
              'draftFlag',
            ],
          ]) {
            expect(
              stored[key],
              isA<int>(),
              reason: '$key reproduces stored legacy data',
            );
          }
          // Read through the real visibility query and row mapper.
          final feed = await receipts.attentionFeed(
            accountId: _authorId,
            view: AttentionFeedView.unread,
            surface: AttentionSurface.myWork,
          );
          expect(feed.page.items, hasLength(1));
          final receipt = feed.page.items.single;
          expect(receipt.presentationPayload['eventType'], eventType);
          expect(receipt.presentationPayload['beaconId'], _beaconId);
          return receipt;
        }

        test(
          'attentionFeed returns the persisted $eventType receipt',
          () async {
            final persisted = await writeAndReadReceipt();
            final field = QueryAttention(query: receipts).attentionFeed;

            final result =
                await field.resolve!(null, {
                      kGlobalInputQueryJwt: const JwtEntity(sub: _authorId),
                      'view': 'unread',
                      'surface': 'myWork',
                    })
                    as Map;
            final items = (result['page'] as Map)['items'] as List;

            expect((result['summary'] as Map)['unreadTotal'], 1);
            expect(items, hasLength(1));
            _expectSanitizedClosureReceipt(
              items.single as Map,
              persisted,
              eventType,
            );
          },
        );

        test(
          'myWorkAttention returns the persisted $eventType receipt',
          () async {
            final persisted = await writeAndReadReceipt();
            final field = QueryAttention(query: receipts).myWorkAttention;

            final result =
                await field.resolve!(null, {
                      kGlobalInputQueryJwt: const JwtEntity(sub: _authorId),
                      'beaconIds': [_beaconId],
                    })
                    as List;

            expect(result, hasLength(1));
            final projection = result.single as Map;
            expect(projection['beaconId'], _beaconId);
            expect(projection['unseenCount'], 1);
            _expectSanitizedClosureReceipt(
              projection['latestUnseen'] as Map,
              persisted,
              eventType,
            );
          },
        );
      }
    },
    skip: skipReason,
  );
}

void _expectSanitizedClosureReceipt(
  Map<dynamic, dynamic> mapped,
  AttentionReceipt persisted,
  String eventType,
) {
  expect(mapped['id'], persisted.id);
  expect(mapped['beaconId'], _beaconId);
  expect(mapped['title'], persisted.title);
  expect(mapped['body'], persisted.body);
  expect(mapped['actionUrl'], persisted.actionUrl);
  expectSanitizedAttentionPayload(
    mapped['presentationPayloadJson'],
    requiredFields: {'eventType': eventType, 'beaconId': _beaconId},
    coercibleFields: {
      'epoch': '2',
      if (eventType == 'closureFinalized') ...{
        'outcome': '1',
        'band': '3',
        'draftFlag': '0',
      },
    },
  );
}
