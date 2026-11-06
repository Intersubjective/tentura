@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:uuid/uuid.dart';
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/notification_preference_case.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/commitment_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'UfhelpAuthor';
const _first = 'UfhelpFirst';
const _second = 'UfhelpSecond';
const _helper = 'UfhelpHelper';
const _otherHelper = 'UfhelpOther';
const _offPath = 'UfhelpOffpath';
const _beacon = 'BfhelpRequest';
const _title = 'Need a van on Saturday';
const _names = {
  _author: 'Anna Author',
  _first: 'Boris First',
  _second: 'Fay Second',
  _helper: 'Vera Helper',
  _otherHelper: 'Nina Helper',
  _offPath: 'Olga Offpath',
};

// Use production DI: new receipt dependencies must be wired into the public
// acceptance and closure actions, rather than called directly by this test.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_HELPED_UPDATES_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_helped',
  );
  final skipReason = await pgSkipReason(target);

  group('forwarders see the help their forwards brought', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late HelpOfferCase offers;
    late CoordinationCase coordination;
    late ClosureCase closure;
    late AttentionAckPort acknowledgements;
    late QueryAttention updates;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          maxConnectionCount: testPoolSizeOverride(),
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      database = getIt<TenturaDb>();
      offers = getIt<HelpOfferCase>();
      coordination = getIt<CoordinationCase>();
      closure = getIt<ClosureCase>();
      acknowledgements = getIt<AttentionAckPort>();
      updates = QueryAttention(query: getIt<AttentionQueryPort>());
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> forward(
      String id,
      String sender,
      String recipient, {
      required int hoursAgo,
      String? parent,
      bool cancelled = false,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id,
   created_at, cancelled_at)
VALUES (@id, @beacon, @sender, @recipient, @parent,
  now() - make_interval(hours => @hoursAgo),
  CASE WHEN @cancelled THEN now() - interval '30 minutes' ELSE NULL END)
'''),
      parameters: {
        'id': id,
        'beacon': _beacon,
        'sender': sender,
        'recipient': recipient,
        'parent': parent,
        'hoursAgo': hoursAgo,
        'cancelled': cancelled,
      },
    );

    Future<void> seedForwardingRoute() async {
      await writer.execute('''
TRUNCATE public.trust_evidence, public.notification_outbox,
  public.attention_occurrence_recipient, public.attention_occurrence,
  public.user_block, public.beacon, public."user" CASCADE
''');
      var slot = 0;
      for (final entry in _names.entries) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
          parameters: {
            'id': entry.key,
            'name': entry.value,
            'key': pgTestPublicKey('forwardhelped', ++slot),
          },
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, @title, 'Moving day', @status)
'''),
        parameters: {
          'id': _beacon,
          'author': _author,
          'title': _title,
          'status': BeaconStatus.open.smallintValue,
        },
      );
      // Winning route A -> F1 -> F2 -> H, plus a newer cancelled arrival
      // through an off-path person. Only the canonical live route earns thanks.
      await forward('FfhelpAFirst', _author, _first, hoursAgo: 6);
      await forward(
        'FfhelpFirstSecond',
        _first,
        _second,
        parent: 'FfhelpAFirst',
        hoursAgo: 5,
      );
      await forward(
        'FfhelpSecondHelper',
        _second,
        _helper,
        parent: 'FfhelpFirstSecond',
        hoursAgo: 4,
      );
      await forward('FfhelpAOffpath', _author, _offPath, hoursAgo: 3);
      await forward(
        'FfhelpOffpathHelper',
        _offPath,
        _helper,
        parent: 'FfhelpAOffpath',
        hoursAgo: 2,
        cancelled: true,
      );
    }

    setUp(seedForwardingRoute);

    Future<void> accept(String helper) async {
      await offers.offerHelp(beaconId: _beacon, userId: helper);
      await coordination.acceptHelpOffer(
        beaconId: _beacon,
        offerUserId: helper,
        actorUserId: _author,
      );
    }

    Future<List<Map<String, dynamic>>> receipts(String account) async => [
      for (final row in await writer.execute(
        Sql.named('''
SELECT id, requires_action, seen_at, suppression_class, presentation_payload
FROM public.notification_outbox
WHERE beacon_id = @beacon AND account_id = @account
  AND presentation_payload->>'eventType' = 'forwardHelped'
ORDER BY id
'''),
        parameters: {'beacon': _beacon, 'account': account},
      ))
        row.toColumnMap(),
    ];

    Future<List<Map<String, Object?>>> visibleUpdates(
      String account, {
      bool unread = false,
    }) async {
      final Object? result = await updates.attentionFeed.resolve!(null, {
        kGlobalInputQueryJwt: JwtEntity(sub: account),
        'view': unread ? 'unread' : 'all',
      });
      if (result case {'page': {'items': final List<Object?> items}}) {
        return [
          for (final item in items)
            if (item case final Map<String, Object?> fields)
              fields
            else
              throw StateError('Updates returned an invalid receipt'),
        ];
      }
      throw StateError('Updates returned an invalid page');
    }

    Map<String, Object?> payload(Map<String, Object?> item) {
      if (item['presentationPayloadJson'] case final String json) {
        final Object? decoded = jsonDecode(json);
        if (decoded case final Map<String, Object?> fields) return fields;
      }
      throw StateError('Updates returned an invalid presentation payload');
    }

    Future<Map<String, Object?>> helpedUpdate(
      String account, {
      bool unread = false,
    }) async {
      final items = (await visibleUpdates(account, unread: unread))
          .where((item) => payload(item)['eventType'] == 'forwardHelped')
          .toList();
      expect(items, hasLength(1), reason: 'one visible forward-help update');
      return items.single;
    }

    Future<void> finalize() async {
      // With fewer than three members close() invokes the real finalizer
      // immediately. No clock manipulation or direct finalizer invocation.
      await closure.close(authorId: _author, beaconId: _beacon);
      final epoch = await ClosureRepository(database).latestEpoch(_beacon);
      expect(epoch, isNotNull);
      expect(epoch!.status, ClosureEpochStatus.finalized);
      expect(epoch.finalizedAt, isNotNull);
    }

    group('forward help channel delivery', () {
      late NotificationPreferenceRepository preferences;
      late AttentionChannelDeliveryRepository deliveries;
      late _ForwardPushRemote remote;
      late FcmBatchQueue queue;
      late BeaconNotificationService channels;
      late DateTime claimAt;

      setUp(() {
        preferences = NotificationPreferenceRepository(database);
        deliveries = AttentionChannelDeliveryRepository(database);
        remote = _ForwardPushRemote();
        final logger = Logger('ForwardHelpChannels');
        queue = FcmBatchQueue(remote, logger);
        channels = BeaconNotificationService(
          queue,
          _ForwardTokens(),
          remote,
          preferences,
          _NoImmediateEmail(),
          logger,
        );
        claimAt = DateTime.timestamp().add(const Duration(days: 1));
      });
      tearDown(() => queue.dispose());

      Future<void> setPreferences(String account, String locale) async {
        await NotificationPreferenceCase(preferences).update(
          accountId: account,
          locale: locale,
        );
      }

      // Identify the category from the same Activity response its recipient
      // reads, then restore the fixture so preferences precede the tested event.
      // This permits either an existing category or a new default-on category.
      Future<NotificationCategory> identifyHelpCategory() async {
        await accept(_helper);
        final item = await helpedUpdate(_first);
        final name = item['category'];
        expect(
          name,
          isA<String>(),
          reason: 'the update exposes its settings category',
        );
        final category = notificationCategoryFromName(name! as String);
        expect(
          category,
          isNotNull,
          reason: 'the category is recognized by notification settings',
        );
        await seedForwardingRoute();
        return category!;
      }

      Future<void> setCategoryChannels({
        required String account,
        required NotificationCategory category,
        required bool push,
        required bool email,
        bool onlyMatchingCategory = false,
      }) async {
        final settings = NotificationPreferenceCase(preferences);
        final current = await settings.getForAccount(account);
        final nextPush = onlyMatchingCategory
            ? (push ? {category} : <NotificationCategory>{})
            : (push
                  ? current.pushCategories.union({category})
                  : current.pushCategories.difference({category}));
        final nextEmail = onlyMatchingCategory
            ? (email ? {category} : <NotificationCategory>{})
            : (email
                  ? current.emailCategories.union({category})
                  : current.emailCategories.difference({category}));
        await settings.update(
          accountId: account,
          pushCategories: [for (final value in nextPush) value.name],
          emailCategories: [for (final value in nextEmail) value.name],
        );
        final persisted = await settings.getForAccount(account);
        expect(persisted.pushCategories, nextPush);
        expect(persisted.emailCategories, nextEmail);
      }

      // Real dispatch jobs are claimed and delivered as in the worker. Only
      // device tokens and the remote FCM endpoint are replaced.
      Future<void> deliver() async {
        for (var round = 0; round < 10; round++) {
          final jobs = await deliveries.claimDue(
            workerId: 'forward-help-channels',
            now: claimAt,
            limit: 50,
          );
          claimAt = claimAt.add(const Duration(minutes: 5));
          if (jobs.isEmpty) break;
          await channels.handOffChannels([
            for (final job in jobs) job.decision,
          ]);
          for (final job in jobs) {
            await deliveries.markDelivered(
              id: job.id,
              workerId: 'forward-help-channels',
            );
          }
        }
        // The production queue flushes once a second, including the negative
        // control where no message is expected.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }

      List<FcmNotificationEntity> pushes(String account) => [
        for (final sent in remote.sent)
          if (sent.tokens.contains('token-$account')) sent.message,
      ];

      void expectAcceptedCopy(String text, String locale) {
        expect(text, contains(_title));
        for (final name in _names.values.take(4)) {
          expect(
            text,
            contains(name),
            reason: 'the canonical help path is named',
          );
        }
        if (locale == 'ru') {
          expect(text.toLowerCase(), contains('помог'));
          expect(text.toLowerCase(), contains('предлож'));
          expect(text, isNot(contains('offered help with')));
        } else {
          expect(text, contains('Your forward helped'));
          expect(text, contains('offered help with «$_title»'));
        }
      }

      Future<_ForwardDigestSender> digest() async {
        final sender = _ForwardDigestSender();
        final env = getIt<Env>();
        final now = DateTime.timestamp().toUtc();
        final due = DateTime.utc(
          now.year,
          now.month,
          now.day + 2,
          env.emailDigestHour,
        );
        await EmailDigestCase(
          preferences,
          NotificationOutboxRepository(database),
          _ForwardContacts(),
          sender,
          EmailLinkBuilder(env),
          env,
          Logger('ForwardHelpDigest'),
          getIt<BeaconAccessGuard>(),
        ).runDue(now: due);
        return sender;
      }

      test(
        'the help update category is enabled by default for push and email',
        () async {
          final category = await identifyHelpCategory();
          // There is no saved preference row after restoring this fresh account.
          final defaults = await NotificationPreferenceCase(
            preferences,
          ).getForAccount(_first);
          expect(defaults.pushCategories, contains(category));
          expect(defaults.emailCategories, contains(category));
          await accept(_helper);
          expect((await helpedUpdate(_first))['category'], category.name);
          await deliver();
          expect(pushes(_first), hasLength(1));
          expectAcceptedCopy(
            '${pushes(_first).single.title} ${pushes(_first).single.body}',
            'en',
          );
          final sender = await digest();
          final messages = sender.sent
              .where((m) => m.to == '$_first@example.com')
              .toList();
          expect(messages, hasLength(1));
          expectAcceptedCopy(messages.single.rendered.text, 'en');
        },
      );

      for (final locale in ['en', 'ru']) {
        test(
          'accepted help sends one localized push to the forwarder in $locale',
          () async {
            await setPreferences(_first, locale);
            await accept(_helper);
            expect(await receipts(_first), hasLength(1));
            await deliver();
            expect(pushes(_first), hasLength(1));
            final message = pushes(_first).single;
            expectAcceptedCopy('${message.title} ${message.body}', locale);
            expect(message.actionUrl, contains(_beacon));
            await deliver();
            expect(
              pushes(_first),
              hasLength(1),
              reason: 'worker polling must not repeat the push',
            );
          },
        );

        test(
          'the next digest includes accepted help in the forwarder locale $locale',
          () async {
            await setPreferences(_first, locale);
            await accept(_helper);
            final sender = await digest();
            final messages = sender.sent
                .where((m) => m.to == '$_first@example.com')
                .toList();
            expect(messages, hasLength(1));
            expect(messages.single.locale, locale);
            expectAcceptedCopy(messages.single.rendered.text, locale);
            expect(messages.single.rendered.html, contains(_title));
            final again = await digest();
            expect(
              again.sent.where((m) => m.to == '$_first@example.com'),
              isEmpty,
            );
          },
        );

        test(
          'a completed request returns in the next digest with localized helper credit in $locale',
          () async {
            await setPreferences(_first, locale);
            await accept(_helper);
            final accepted = await digest();
            expect(
              accepted.sent.where((m) => m.to == '$_first@example.com'),
              hasLength(1),
            );
            await finalize();
            final completed = await digest();
            final messages = completed.sent
                .where((m) => m.to == '$_first@example.com')
                .toList();
            expect(
              messages,
              hasLength(1),
              reason:
                  'completion is new digest activity after the acceptance was emailed',
            );
            final text = messages.single.rendered.text;
            expect(messages.single.locale, locale);
            expect(text, contains(_title));
            expect(text, contains(_names[_helper]));
            if (locale == 'ru') {
              expect(text.toLowerCase(), contains('заверш'));
              expect(text.toLowerCase(), contains('помощ'));
              expect(text, isNot(contains('was completed with')));
            } else {
              expect(
                text,
                contains(
                  "«$_title» was completed with ${_names[_helper]}'s help",
                ),
              );
            }
            final again = await digest();
            expect(
              again.sent.where((m) => m.to == '$_first@example.com'),
              isEmpty,
            );
          },
        );

        test(
          'completion sends one fresh localized push after acceptance in $locale',
          () async {
            await setPreferences(_first, locale);
            await accept(_helper);
            await deliver();
            // The done notification is observed independently of acceptance.
            remote.sent.clear();
            await finalize();
            await deliver();
            expect(pushes(_first), hasLength(1));
            final message = pushes(_first).single;
            final text = '${message.title} ${message.body}';
            expect(text, contains(_title));
            expect(text, contains(_names[_helper]));
            if (locale == 'ru') {
              expect(text.toLowerCase(), contains('заверш'));
              expect(text.toLowerCase(), contains('помощ'));
              expect(text, isNot(contains('was completed with')));
            } else {
              expect(
                text,
                contains(
                  "«$_title» was completed with ${_names[_helper]}'s help",
                ),
              );
            }
            await deliver();
            expect(
              pushes(_first),
              hasLength(1),
              reason: 'done is pushed only once',
            );
          },
        );
      }

      test(
        'category push opt out silences a forwarder while another receives help',
        () async {
          final category = await identifyHelpCategory();
          await setCategoryChannels(
            account: _first,
            category: category,
            push: false,
            email: true,
          );
          // Only the identified category is on for the positive control, so a
          // push under some unrelated category cannot make this test pass.
          await setCategoryChannels(
            account: _second,
            category: category,
            push: true,
            email: true,
            onlyMatchingCategory: true,
          );
          await accept(_helper);
          await deliver();
          expect(pushes(_first), isEmpty);
          expect(
            pushes(_second),
            hasLength(1),
            reason: 'positive control proves delivery occurred',
          );
          expectAcceptedCopy(
            '${pushes(_second).single.title} ${pushes(_second).single.body}',
            'en',
          );
          expect(
            await receipts(_first),
            hasLength(1),
            reason: 'push opt out leaves the in-app update',
          );
          remote.sent.clear();
          await finalize();
          await deliver();
          expect(
            pushes(_first),
            isEmpty,
            reason: 'completion honours push opt out too',
          );
          expect(
            pushes(_second),
            hasLength(1),
            reason: 'an opted-in forwarder receives the new completion push',
          );
          final done = pushes(_second).single;
          expect(
            '${done.title} ${done.body}',
            contains("«$_title» was completed with ${_names[_helper]}'s help"),
          );
          await deliver();
          expect(pushes(_first), isEmpty);
          expect(
            pushes(_second),
            hasLength(1),
            reason: 'the completion push is not repeated',
          );
        },
      );

      test(
        'completion push follows the help category setting for each forwarder',
        () async {
          final category = await identifyHelpCategory();
          await setCategoryChannels(
            account: _first,
            category: category,
            push: false,
            email: true,
          );
          await setCategoryChannels(
            account: _second,
            category: category,
            push: true,
            email: true,
            onlyMatchingCategory: true,
          );
          await accept(_helper);
          await deliver();
          // Observe completion independently: missing acceptance delivery must
          // not prevent this test from reaching the done-delivery assertions.
          remote.sent.clear();
          await finalize();
          await deliver();
          expect(
            pushes(_first),
            isEmpty,
            reason: 'the matching category is off',
          );
          expect(
            pushes(_second),
            hasLength(1),
            reason: 'the opted-in forwarder receives completion',
          );
          final done = pushes(_second).single;
          expect(
            '${done.title} ${done.body}',
            contains("«$_title» was completed with ${_names[_helper]}'s help"),
          );
          await deliver();
          expect(pushes(_first), isEmpty);
          expect(pushes(_second), hasLength(1));
        },
      );

      test(
        'category email opt out excludes a forwarder while another gets the digest',
        () async {
          final category = await identifyHelpCategory();
          await setCategoryChannels(
            account: _first,
            category: category,
            push: true,
            email: false,
          );
          await setCategoryChannels(
            account: _second,
            category: category,
            push: true,
            email: true,
            onlyMatchingCategory: true,
          );
          await accept(_helper);
          final sender = await digest();
          expect(
            sender.sent.where((m) => m.to == '$_first@example.com'),
            isEmpty,
          );
          final control = sender.sent
              .where((m) => m.to == '$_second@example.com')
              .toList();
          expect(
            control,
            hasLength(1),
            reason: 'positive control proves the digest ran',
          );
          expectAcceptedCopy(control.single.rendered.text, 'en');
          expect(await receipts(_first), hasLength(1));
          await finalize();
          final completed = await digest();
          expect(
            completed.sent.where((m) => m.to == '$_first@example.com'),
            isEmpty,
          );
          final doneControl = completed.sent
              .where((m) => m.to == '$_second@example.com')
              .toList();
          expect(doneControl, hasLength(1));
          expect(
            doneControl.single.rendered.text,
            contains("«$_title» was completed with ${_names[_helper]}'s help"),
          );
        },
      );
    });

    test('acceptance thanks every canonical path forwarder in Updates '
        'without a My desk obligation', () async {
      await accept(_helper);

      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(stored, hasLength(1), reason: '$account forwarded on the path');
        expect(stored.single['requires_action'], isFalse);
        expect(stored.single['suppression_class'], 'standard');
        final item = await helpedUpdate(account, unread: true);
        expect(item['id'], stored.single['id']);
        expect(item['requiresAction'], isFalse);
        expect(item['title'], contains('Your forward helped'));
        expect(item['title'], isNot(contains('Done')));
        expect(payload(item), containsPair('beaconId', _beacon));
        expect(payload(item), containsPair('beaconTitle', _title));
        expect(payload(item), containsPair('helperId', _helper));
        expect(payload(item), containsPair('authorId', _author));
        expect(payload(item)['path'], [
          _named(_author),
          _named(_first),
          _named(_second),
          _named(_helper),
        ]);
        final obligations = await updates.liveObligationBeacons.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: account),
        });
        expect(obligations, isNot(contains(_beacon)));
        final summary =
            await updates.attentionSurfaceSummary.resolve!(null, {
                  kGlobalInputQueryJwt: JwtEntity(sub: account),
                })
                as Map;
        expect(summary['myDeskCount'], 0);
        expect(summary['myDeskDot'], isFalse);
      }
      for (final account in [_author, _helper, _otherHelper, _offPath]) {
        expect(
          await receipts(account),
          isEmpty,
          reason: '$account is not a path forwarder',
        );
        expect(
          (await visibleUpdates(account)).where(
            (item) => payload(item)['eventType'] == 'forwardHelped',
          ),
          isEmpty,
        );
      }
    });

    test('another accepted helper through the same forwarder updates one '
        'item to two people', () async {
      await accept(_helper);
      final before = await receipts(_first);
      await forward(
        'FfhelpFirstOther',
        _first,
        _otherHelper,
        parent: 'FfhelpAFirst',
        hoursAgo: 1,
      );
      await accept(_otherHelper);

      for (final account in [_author, _helper, _otherHelper]) {
        expect(
          await receipts(account),
          isEmpty,
          reason: 'later acceptances still thank only path forwarders',
        );
        expect(
          (await visibleUpdates(account)).where(
            (item) => payload(item)['eventType'] == 'forwardHelped',
          ),
          isEmpty,
        );
      }
      expect(await receipts(_first), hasLength(1));
      final after = await helpedUpdate(_first);
      expect(before, hasLength(1));
      expect(after['id'], before.single['id']);
      expect(after['collapsedCount'], 2);
      expect(after['title'], contains('Your forward helped 2 people'));
      final second = await helpedUpdate(_second);
      expect(
        second['collapsedCount'],
        1,
        reason: 'the second helper bypassed F2',
      );
      expect(await receipts(_second), hasLength(1));
      expect(await receipts(_otherHelper), isEmpty);
    });

    test('finalization upgrades the same read items to Done and makes them '
        'unread again', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      final seen = <String, List<Map<String, dynamic>>>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
        seen[account] = await receipts(account);
      }

      await finalize();

      for (final account in [_first, _second]) {
        expect(await receipts(account), hasLength(1));
        final item = await helpedUpdate(account, unread: true);
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(seen[account]!.single['seen_at'], isNotNull);
        expect(item['id'], before[account]!.single['id']);
        expect(item['title'], contains('Done ✓'));
        expect(item['seenAt'], isNull);
        expect(item['requiresAction'], isFalse);
        expect(item['collapsedCount'], 1);
      }
    });

    test(
      'finalization upgrades a shared forwarder receipt for a retained '
      'helper and leaves the withdrawn-only forwarder receipt unchanged',
      () async {
        await accept(_helper);
        await forward(
          'FfhelpFirstOther',
          _first,
          _otherHelper,
          parent: 'FfhelpAFirst',
          hoursAgo: 1,
        );
        await accept(_otherHelper);
        final before = <String, List<Map<String, dynamic>>>{};
        final marked = <String, int>{};
        final seen = <String, List<Map<String, dynamic>>>{};
        final visibleBefore = <String, List<Map<String, Object?>>>{};
        for (final account in [_first, _second]) {
          before[account] = await receipts(account);
          visibleBefore[account] = (await visibleUpdates(account))
              .where((item) => payload(item)['eventType'] == 'forwardHelped')
              .toList();
          marked[account] = await acknowledgements.markSeen(
            accountId: account,
            ids: before[account]!.map((row) => row['id'] as String).toList(),
          );
          seen[account] = await receipts(account);
        }
        // Keep H's voluntary departure in the closure snapshot by moving their
        // commitment history beyond the existing acknowledgement grace window.
        await writer.execute(
          Sql.named('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - make_interval(secs => @elapsedSeconds)
WHERE beacon_id = @beacon AND user_id = @helper
'''),
          parameters: {
            'elapsedSeconds': kCommitmentGracePeriod.inSeconds + 1,
            'beacon': _beacon,
            'helper': _helper,
          },
        );
        await offers.withdraw(
          beaconId: _beacon,
          userId: _helper,
          withdrawReason: 'timing',
        );

        await finalize();

        final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
        final members = await ClosureRepository(database).members(
          beaconId: _beacon,
          epoch: epoch.epoch,
        );
        expect(members, hasLength(2));
        expect(
          members.singleWhere((member) => member.userId == _helper).departure,
          Departure.voluntary,
        );
        expect(
          members
              .singleWhere((member) => member.userId == _otherHelper)
              .departure,
          isNull,
        );
        for (final account in [_author, _helper, _otherHelper]) {
          expect(
            await receipts(account),
            isEmpty,
            reason: 'finalization still thanks only path forwarders',
          );
          expect(
            (await visibleUpdates(account)).where(
              (item) => payload(item)['eventType'] == 'forwardHelped',
            ),
            isEmpty,
          );
        }
        for (final account in [_first, _second]) {
          expect(await receipts(account), hasLength(1));
          expect(before[account], hasLength(1));
          expect(marked[account], 1);
          expect(seen[account]!.single['seen_at'], isNotNull);
          expect(visibleBefore[account], hasLength(1));
        }
        // F1 brought both helpers; H2 is still present. Its one collapsed item
        // upgrades even though H withdrew, and the historical count stays two.
        final first = await helpedUpdate(_first, unread: true);
        expect(first['id'], before[_first]!.single['id']);
        expect(first['title'], contains('Done ✓'));
        expect(first['seenAt'], isNull);
        expect(first['collapsedCount'], 2);
        expect(first['requiresAction'], isFalse);
        // F2 brought only H: its old receipt, copy, payload and read timestamp
        // survive finalization without receiving H2's unrelated Done upgrade.
        final second = await helpedUpdate(_second);
        expect(second['id'], before[_second]!.single['id']);
        expect(second['title'], visibleBefore[_second]!.single['title']);
        expect(second['body'], visibleBefore[_second]!.single['body']);
        expect(
          second['presentationPayloadJson'],
          visibleBefore[_second]!.single['presentationPayloadJson'],
        );
        expect(second['title'], isNot(contains('Done')));
        expect(second['collapsedCount'], 1);
        expect(
          (await receipts(_second)).single['seen_at'],
          seen[_second]!.single['seen_at'],
        );
        expect(second['seenAt'], isNotNull);
        expect(second['requiresAction'], isFalse);
      },
    );

    test('a withdrawn helper leaves the forwarders update intact and read '
        'without a Done upgrade at finalization', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
      }
      await offers.withdraw(
        beaconId: _beacon,
        userId: _helper,
        withdrawReason: 'timing',
      );
      final afterWithdrawal = <String, List<Map<String, dynamic>>>{
        for (final account in [_first, _second])
          account: await receipts(account),
      };
      // A direct helper keeps an actual closure epoch, but their route has
      // no forwarder. Thus finalize runs without crediting F1/F2 for them.
      await forward('FfhelpADirect', _author, _otherHelper, hoursAgo: 1);
      await accept(_otherHelper);
      await finalize();
      final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
      final members = await ClosureRepository(
        database,
      ).members(beaconId: _beacon, epoch: epoch.epoch);
      expect(
        members
            .where((member) => member.departure == null)
            .map((member) => member.userId),
        [_otherHelper],
      );
      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(stored, hasLength(1));
        final item = await helpedUpdate(account);
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(afterWithdrawal[account], hasLength(1));
        expect(
          afterWithdrawal[account]!.single['id'],
          before[account]!.single['id'],
        );
        expect(item['id'], before[account]!.single['id']);
        expect(
          stored.single['presentation_payload'],
          before[account]!.single['presentation_payload'],
        );
        expect(item['title'], isNot(contains('Done')));
        expect(item['seenAt'], isNotNull);
        expect(item['collapsedCount'], 1);
      }
    });

    test('withdrawing the only accepted helper preserves the same read '
        'forwarder receipts without Done when finalized', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      final seen = <String, List<Map<String, dynamic>>>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
        seen[account] = await receipts(account);
      }
      // Match the closure lifecycle fixtures: move past the acknowledgement
      // grace window without waiting a day. Inside that window withdrawal
      // voids membership, so close() would skip the finalizer entirely.
      await writer.execute(
        Sql.named('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - make_interval(secs => @elapsedSeconds)
WHERE beacon_id = @beacon AND user_id = @helper
'''),
        parameters: {
          'elapsedSeconds': kCommitmentGracePeriod.inSeconds + 1,
          'beacon': _beacon,
          'helper': _helper,
        },
      );
      await offers.withdraw(
        beaconId: _beacon,
        userId: _helper,
        withdrawReason: 'timing',
      );
      final afterWithdrawal = <String, List<Map<String, dynamic>>>{
        for (final account in [_first, _second])
          account: await receipts(account),
      };

      await finalize();

      final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
      final members = await ClosureRepository(database).members(
        beaconId: _beacon,
        epoch: epoch.epoch,
      );
      expect(
        members,
        hasLength(1),
        reason: 'no replacement helper was admitted',
      );
      expect(members.single.userId, _helper);
      expect(members.single.departure, Departure.voluntary);
      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(
          stored,
          hasLength(1),
          reason: 'withdrawal never retracts the update',
        );
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(afterWithdrawal[account], hasLength(1));
        final original = before[account]!.single;
        expect(afterWithdrawal[account]!.single['id'], original['id']);
        expect(stored.single['id'], original['id']);
        expect(
          stored.single['presentation_payload'],
          original['presentation_payload'],
        );
        expect(seen[account]!.single['seen_at'], isNotNull);
        expect(stored.single['seen_at'], seen[account]!.single['seen_at']);
        final item = await helpedUpdate(account);
        expect(item['id'], original['id']);
        expect(item['title'], contains('Your forward helped'));
        expect(item['title'], isNot(contains('Done')));
        expect(item['seenAt'], isNotNull);
        expect(item['collapsedCount'], 1);
      }
    });

    for (final reverseBlock in [false, true]) {
      test(
        'the Updates payload masks a path person who '
        '${reverseBlock ? 'blocked the recipient' : 'the recipient blocked'}',
        () async {
          await writer.execute(
            Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
            parameters: {
              'blocker': reverseBlock ? _second : _first,
              'blocked': reverseBlock ? _first : _second,
            },
          );
          await accept(_helper);

          final first = await helpedUpdate(_first);
          expect(payload(first)['path'], [
            _named(_author),
            _named(_first),
            _anonymous(1),
            _named(_helper),
          ]);
          final publicCopy = jsonEncode(first);
          expect(publicCopy, isNot(contains(_second)));
          expect(publicCopy, isNot(contains(_names[_second])));
          final second = await helpedUpdate(_second);
          expect(payload(second)['path'], [
            _named(_author),
            _anonymous(1),
            _named(_second),
            _named(_helper),
          ]);
          expect(await receipts(_first), hasLength(1));
          expect(await receipts(_second), hasLength(1));
        },
      );
    }

    test('an acceptance cannot commit when its forwarder receipt cannot '
        'be saved', () async {
      await offers.offerHelp(beaconId: _beacon, userId: _helper);
      await writer.execute(r'''
CREATE FUNCTION public.reject_forward_helped_test_receipt() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.presentation_payload->>'eventType' = 'forwardHelped' THEN
    RAISE EXCEPTION 'forward helped receipt unavailable';
  END IF;
  RETURN NEW;
END;
$$;
''');
      await writer.execute('''
CREATE TRIGGER reject_forward_helped_test_receipt
BEFORE INSERT OR UPDATE ON public.notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.reject_forward_helped_test_receipt();
''');
      try {
        await expectLater(
          coordination.acceptHelpOffer(
            beaconId: _beacon,
            offerUserId: _helper,
            actorUserId: _author,
          ),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains(
                'forward helped receipt unavailable',
              ),
            ),
          ),
          reason: 'acceptance and every path receipt are one atomic action',
        );
        final admitted = await writer.execute(
          Sql.named(
            'SELECT count(*) FROM public.beacon_participant WHERE beacon_id = @beacon AND user_id = @helper',
          ),
          parameters: {'beacon': _beacon, 'helper': _helper},
        );
        expect(admitted.single.single, 0);
        for (final account in [_first, _second, _helper]) {
          expect(await receipts(account), isEmpty);
        }
      } finally {
        await writer.execute(
          'DROP TRIGGER reject_forward_helped_test_receipt ON public.notification_outbox',
        );
        await writer.execute(
          'DROP FUNCTION public.reject_forward_helped_test_receipt()',
        );
      }
    });
  }, skip: skipReason);
}

Matcher _named(String id) => allOf(
  containsPair('userId', id),
  containsPair('displayName', _names[id]),
  containsPair('anonymousCount', 0),
);

Matcher _anonymous(int count) => allOf(
  containsPair('userId', null),
  containsPair('displayName', null),
  containsPair('anonymousCount', count),
);

class _ForwardPushRemote implements FcmRemoteRepositoryPort {
  final sent = <({Set<String> tokens, FcmNotificationEntity message})>[];
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    sent.add((tokens: fcmTokens.toSet(), message: message));
    return [];
  }
}

class _ForwardTokens extends Fake implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [
    FcmTokenEntity(
      userId: userId,
      appId: UuidValue.fromString('00000000-0000-4000-8000-000000000001'),
      platform: 'web',
      token: 'token-$userId',
      createdAt: DateTime.utc(2026),
      lastRefreshedAt: DateTime.utc(2026),
    ),
  ];
}

class _NoImmediateEmail extends Fake implements EmailNotificationPort {
  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {}
}

class _ForwardContacts extends Fake implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      '$accountId@example.com';
}

class _ForwardDigestSender extends Fake implements EmailSenderPort {
  final sent = <({String to, String locale, RenderedEmail rendered})>[];
  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    sent.add((
      to: to,
      locale: locale,
      rendered: const EmailTemplateRenderer().renderDigest(
        content: content,
        locale: locale,
      ),
    ));
  }
}
