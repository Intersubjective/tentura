@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/data/service/email_notification_service.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import '../../support/fake_beacon_access_guard.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Unotifauthor01';
const _bob = 'Unotifbob00001';
const _carol = 'Unotifcarol001';
const _beacon = 'Bnotifpost0001';
const _request = 'Bnotifrequest01';
const _users = [_author, _bob, _carol];
const _kindPost = 1;
const _statusDraft = 3;

/// A Post's arrival and its first response reach push/email as Post copy, and
/// batches of them as Post batch copy; a Request relay keeps its Request copy.
/// The jobs come from real `PostCase.publish`, `ForwardCase.forward` and room
/// writes over real attention dispatch; they are claimed the way the delivery
/// worker claims them and handed to the real notification service and the real
/// FCM batch queue, with only the device transport faked.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_NOTIFICATION_PIPELINE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_notif_pipeline',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post notification pipeline with real dispatch', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _Harness harness;
    late Connection writer;
    late AttentionChannelDeliveryRepository deliveries;
    late _RecordingRemote remote;
    late DateTime nextClaimAt;
    FcmBatchQueue? queue;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _buildHarness(database, target.databaseEnv);
      deliveries = AttentionChannelDeliveryRepository(database);
    });
    setUp(() async {
      await _seed(writer);
      remote = _RecordingRemote();
      nextClaimAt = DateTime.timestamp().add(const Duration(days: 1));
    });
    tearDown(() {
      queue?.dispose();
      queue = null;
    });
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> publish() => harness.posts.publish(
      authorId: _author,
      beaconId: _beacon,
      body: 'Have a look at this',
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: const [_bob, _carol],
      notes: const {},
      forwardPolicy: BeaconForwardPolicyValue.open,
    );

    Future<void> forward({
      required String senderId,
      required String beaconId,
      required List<String> recipientIds,
    }) => harness.forwards.forward(
      senderId: senderId,
      beaconId: beaconId,
      recipientIds: recipientIds,
    );

    /// Every pending delivery job, claimed the way the worker claims them: at
    /// most one job per account per claim, so claim until none are left.
    Future<List<AttentionChannelDecision>> claimJobs() async {
      final claimed = <AttentionChannelDecision>[];
      var now = nextClaimAt;
      // A later handoff must not rewind behind the previous throttle lease.
      nextClaimAt = nextClaimAt.add(const Duration(hours: 1));
      for (var round = 0; round < 10; round++) {
        final jobs = await deliveries.claimDue(
          workerId: 'post-notification-pipeline-test',
          now: now,
          limit: 50,
        );
        if (jobs.isEmpty) break;
        for (final job in jobs) {
          claimed.add(job.decision);
          await deliveries.markDelivered(
            id: job.id,
            workerId: 'post-notification-pipeline-test',
          );
        }
        now = now.add(const Duration(minutes: 5));
      }
      return claimed;
    }

    List<AttentionChannelDecision> forRecipient(
      List<AttentionChannelDecision> jobs,
      String recipientId,
    ) => [
      for (final job in jobs)
        if (job.recipientId == recipientId) job,
    ];

    /// Hands [jobs] to the real notification service and returns what the real
    /// batch queue finally sends. The queue is built here so its one-second
    /// flush cannot fire between two hand-offs of the same window.
    Future<List<FcmNotificationEntity>> pushed(
      List<AttentionChannelDecision> jobs, {
      Map<String, String> locales = const {},
    }) async {
      final logger = Logger('PostNotificationPipelinePgTest');
      final batch = queue = FcmBatchQueue(remote, logger);
      final channels = BeaconNotificationService(
        batch,
        _Tokens(),
        remote,
        _Preferences(locales),
        _SilentEmail(),
        logger,
      );
      await channels.handOffChannels(jobs);
      final deadline = DateTime.timestamp().add(const Duration(seconds: 10));
      while (remote.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return remote.sent;
    }

    group('email for Posts shared with a note', () {
      late NotificationPreferenceRepository preferences;
      late _PostEmailSender sender;
      late _TrackedEmail email;
      late BeaconNotificationService channels;
      late Env emailEnv;

      Future<void> preparePost({
        String beaconId = _beacon,
        String body = 'A neighbourhood story',
      }) async {
        // Bob may forward this Post; Carol has not received it yet.
        await harness.posts.publish(
          authorId: _author,
          beaconId: beaconId,
          body: body,
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [_bob],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.open,
        );
        await claimJobs();
      }

      Future<void> prepareAnotherPost(String beaconId) async {
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon
              (id, user_id, title, description, status, kind, forward_policy, is_discoverable)
            VALUES (@id, @author, '', '', 3, 1, 1, false)
          '''),
          parameters: {'id': beaconId, 'author': _author},
        );
        await preparePost(beaconId: beaconId, body: 'A different story');
      }

      Future<void> resetHistory() async {
        await _seed(writer);
        await preparePost();
      }

      setUp(() async {
        preferences = NotificationPreferenceRepository(database);
        sender = _PostEmailSender();
        emailEnv = Env(
          environment: 'test',
          publicOrigin: 'https://tentura.example',
          unsubscribeSigningSecret: 'post-share-email-test-secret',
          printEnv: false,
        );
        GetIt.I.pushNewScope(
          init: (scope) => scope.registerSingleton<Env>(emailEnv),
        );
        email = _TrackedEmail(
          EmailNotificationService(
            preferences,
            UserPresenceRepository(database),
            sender,
            _PostContacts(),
            NotificationOutboxRepository(database),
            EmailLinkBuilder(emailEnv),
            emailEnv,
            Logger('PostShareEmailTest'),
          ),
        );
        final batch = queue = FcmBatchQueue(
          remote,
          Logger('PostShareEmailTest'),
        );
        channels = BeaconNotificationService(
          batch,
          _Tokens(),
          remote,
          preferences,
          email,
          Logger('PostShareEmailTest'),
        );
        await preparePost();
      });

      tearDown(() => GetIt.I.popScope());

      Future<void> share({
        String from = _author,
        String beaconId = _beacon,
        String note = 'Read this before Saturday',
      }) async {
        await harness.forwards.forward(
          senderId: from,
          beaconId: beaconId,
          recipientIds: const [_carol],
          sharedNote: note,
        );
      }

      Future<void> deliver() async {
        final jobs = forRecipient(await claimJobs(), _carol);
        await channels.handOffChannels(jobs);
        await email.finish();
      }

      Future<void> digest() =>
          EmailDigestCase(
            preferences,
            NotificationOutboxRepository(database),
            _PostContacts(),
            sender,
            EmailLinkBuilder(emailEnv),
            emailEnv,
            Logger('PostShareEmailTest'),
            FakeBeaconAccessGuard(),
          ).runDue(
            now: DateTime.timestamp()
                .add(const Duration(days: 2))
                .copyWith(hour: emailEnv.emailDigestHour),
          );

      // Every suppression test first demonstrates a deliverable share, so
      // disabling all email delivery cannot satisfy the negative assertions.
      Future<void> expectFirstEmail() async {
        await share();
        await deliver();
        expect(
          sender.immediate,
          hasLength(1),
          reason:
              'An absent recipient with default preferences receives the noted Post immediately',
        );
      }

      for (final storedRow in [false, true]) {
        test(
          '${storedRow ? 'stored' : 'first-use'} notification preferences enable shared Post email by default',
          () async {
            if (storedRow) {
              await writer.execute(
                Sql.named(
                  'INSERT INTO public.notification_preference (account_id) VALUES (@account)',
                ),
                parameters: {'account': _carol},
              );
            }
            final defaults = await preferences.getForAccount(_carol);
            expect(
              defaults.emailCategories.map((category) => category.name),
              contains('postsSharedWithMe'),
              reason:
                  'The server supplies the default; an omitted saved category means opt-out',
            );
          },
        );
      }

      for (final locale in ['en', 'ru']) {
        test(
          '$locale sends one immediate email with the note and Post link by default',
          () async {
            final defaults = await preferences.getForAccount(_carol);
            await preferences.upsert(defaults.copyWith(locale: locale));
            await expectFirstEmail();
            final message = sender.immediate.single;
            expect(message.to, '$_carol@example.com');
            expect(message.locale, locale);
            for (final part in [message.rendered.text, message.rendered.html]) {
              expect(part, contains('Alice'));
              expect(part, contains('Read this before Saturday'));
              expect(
                part,
                contains(
                  locale == 'ru' ? 'Открыть в Tentura' : 'Open in Tentura',
                ),
              );
            }
            expect(
              message.rendered.text,
              contains('Read this before Saturday'),
            );
            expect(message.rendered.text, contains('/beacon/view/$_beacon'));
            expect(message.rendered.text, contains('https://tentura.example'));
            await digest();
            expect(
              sender.digests,
              isEmpty,
              reason:
                  'An immediately emailed share is consumed before the digest',
            );
          },
        );
      }

      test(
        'several noted shares of one Post before delivery collapse to one email',
        () async {
          const otherPost = 'Bnotifotherpost';
          await prepareAnotherPost(otherPost);
          await share();
          await share(from: _bob, note: 'You will like this too');
          // An unrelated, unnoted share must survive for the digest. This
          // makes consuming every pending receipt an incorrect solution.
          await share(from: _bob, beaconId: otherPost, note: '');
          final outbox = NotificationOutboxRepository(database);
          final familyBefore = (await outbox.pendingForAccount(
            _carol,
          )).where((receipt) => receipt.beaconId == _beacon).toList();
          expect(familyBefore, hasLength(2));
          expect(
            familyBefore.map((receipt) => receipt.actorUserId),
            unorderedEquals([_author, _bob]),
          );
          await deliver();
          expect(sender.immediate, hasLength(1));
          final delivered = sender.immediate.single;
          expect(delivered.to, '$_carol@example.com');
          for (final part in [
            delivered.rendered.html,
            delivered.rendered.text,
          ]) {
            expect(part, contains('/beacon/view/$_beacon'));
            expect(part, isNot(contains('/beacon/view/$otherPost')));
            expect(
              part,
              anyOf(
                contains('Read this before Saturday'),
                contains('You will like this too'),
              ),
            );
            if (part.contains('Read this before Saturday')) {
              expect(part, contains('Alice'));
            }
            if (part.contains('You will like this too')) {
              expect(part, contains('Bob'));
            }
          }
          final remaining = await outbox.pendingForAccount(_carol);
          expect(
            remaining.where((receipt) => receipt.beaconId == _beacon),
            isEmpty,
            reason: 'Every share of the emailed Post is consumed',
          );
          expect(
            remaining.where((receipt) => receipt.beaconId == otherPost),
            hasLength(1),
          );
          final emailed = await writer.execute(
            Sql.named('''
              SELECT actor_user_id FROM public.notification_outbox
              WHERE account_id = @account AND beacon_id = @beacon
                AND emailed_at IS NOT NULL
            '''),
            parameters: {'account': _carol, 'beacon': _beacon},
          );
          expect(
            emailed.map((row) => row.first),
            unorderedEquals([_author, _bob]),
          );
          await digest();
          expect(sender.digests, hasLength(1));
          for (final part in [
            sender.digests.single.rendered.text,
            sender.digests.single.rendered.html,
          ]) {
            expect(part, contains('/beacon/view/$otherPost'));
            expect(
              part,
              isNot(contains('/beacon/view/$_beacon')),
              reason:
                  'The immediately emailed family must not appear again in the digest',
            );
          }
        },
      );

      test(
        'a share arriving during immediate email delivery remains available for the digest',
        () async {
          const firstNote = 'Read this before Saturday';
          const laterNote = 'Bob recommends reading this on Sunday';
          await share();
          var sharedDuringSend = false;
          sender.beforeNotificationCompletes = () async {
            // The first message has been rendered, but SMTP has not yet
            // acknowledged it. Commit another sender's share in that window.
            await share(from: _bob, note: laterNote);
            final receipts = await writer.execute(
              Sql.named('''
                SELECT actor_user_id, dedup_key, emailed_at
                FROM public.notification_outbox
                WHERE account_id = @account AND beacon_id = @beacon
              '''),
              parameters: {'account': _carol, 'beacon': _beacon},
            );
            expect(
              receipts.map((row) => row[0]),
              unorderedEquals([_author, _bob]),
            );
            expect(receipts.map((row) => row[1]).toSet(), hasLength(1));
            expect(receipts.every((row) => row[2] == null), isTrue);
            sharedDuringSend = true;
          };

          await deliver();

          expect(sharedDuringSend, isTrue);
          expect(sender.immediate, hasLength(1));
          expect(sender.immediate.single.to, '$_carol@example.com');
          for (final part in [
            sender.immediate.single.rendered.text,
            sender.immediate.single.rendered.html,
          ]) {
            expect(part, contains(firstNote));
            expect(part, isNot(contains(laterNote)));
          }

          await digest();

          expect(
            sender.digests,
            hasLength(1),
            reason:
                'SMTP completion must only consume the rendered receipts; '
                'the concurrent share has not been emailed yet',
          );
          expect(sender.digests.single.to, '$_carol@example.com');
          // Assert the complete rendered item set, not just matching text
          // somewhere in a digest that might also contain other shares.
          expect(
            sender.digests.single.rendered.text
                .split('\n')
                .where((line) => line.startsWith('- ')),
            ['- Bob — A neighbourhood story — Bob: $laterNote'],
          );
          expect(
            RegExp('<li>').allMatches(sender.digests.single.rendered.html),
            hasLength(1),
          );
          for (final part in [
            sender.digests.single.rendered.text,
            sender.digests.single.rendered.html,
          ]) {
            expect(part, contains('Bob'));
            expect(part, contains(laterNote));
            expect(part, contains('/beacon/view/$_beacon'));
            expect(part, isNot(contains(firstNote)));
          }
        },
      );

      test(
        'a later sender sharing the same Post within cooldown sends no second email',
        () async {
          await expectFirstEmail();
          await share(from: _bob, note: 'Another personal recommendation');
          await deliver();
          expect(sender.immediate, hasLength(1));
          final pending =
              (await NotificationOutboxRepository(database).pendingForAccount(
                _carol,
              )).where((receipt) => receipt.beaconId == _beacon).toList();
          expect(
            pending,
            hasLength(1),
            reason: 'Cooldown defers the later share; it must not discard it',
          );
          expect(pending.single.actorUserId, _bob);
          await digest();
          expect(sender.digests, hasLength(1));
          for (final part in [
            sender.digests.single.rendered.text,
            sender.digests.single.rendered.html,
          ]) {
            expect(part, contains('/beacon/view/$_beacon'));
            expect(part, contains('Bob'));
            expect(part, contains('Another personal recommendation'));
          }
          expect(sender.immediate, hasLength(1));
        },
      );

      test(
        'email cooldown also covers a different Post in the same category',
        () async {
          await expectFirstEmail();
          const secondPost = 'Bnotifpost0002';
          await prepareAnotherPost(secondPost);
          await share(beaconId: secondPost, note: 'Another recommendation');
          // The second event uses ForwardCase.forward(sharedNote), just as
          // the first one does, rather than relying on publish-time notes.
          await deliver();
          expect(
            sender.immediate,
            hasLength(1),
            reason: 'Cooldown is per email category, not only per Post',
          );
          // With no prior email history, exactly the same forward must
          // deliver. Otherwise silence above could be a broken second path.
          await resetHistory();
          await prepareAnotherPost(secondPost);
          await share(beaconId: secondPost, note: 'Another recommendation');
          await deliver();
          expect(sender.immediate, hasLength(2));
          expect(
            sender.immediate.last.rendered.text,
            contains('/beacon/view/$secondPost'),
          );
          expect(
            sender.immediate.last.rendered.text,
            contains('Another recommendation'),
          );
        },
      );

      test('muting a Post suppresses its immediate email and digest', () async {
        await expectFirstEmail();
        await resetHistory();
        await share();
        await preferences.setBeaconMute(accountId: _carol, beaconId: _beacon);
        await deliver();
        await digest();
        expect(sender.immediate, hasLength(1));
        expect(
          sender.digests.where((e) => e.to == '$_carol@example.com'),
          isEmpty,
        );
      });

      test(
        'blocking a sharing person suppresses queued immediate and digest email while other senders deliver',
        () async {
          const blockedNote = 'A note from the person I blocked';
          await share(from: _bob, note: blockedNote);
          final blocks = UserBlockRepository(target.databaseEnv, database);
          await blocks.block(
            blockerId: _carol,
            blockedId: _bob,
            cascadeMode: 0,
          );
          expect(await blocks.isBlockedPair(a: _carol, b: _bob), isTrue);
          await deliver();
          expect(
            sender.immediate,
            isEmpty,
            reason:
                'A queued share from a now-blocked sender must not send immediate email',
          );
          await digest();
          expect(
            sender.digests,
            isEmpty,
            reason: 'A blocked sender must not leak through the digest either',
          );

          // Alice is still unblocked and shares the same readable Post. A
          // blanket stop of all Post email cannot satisfy this control.
          await expectFirstEmail();
          for (final part in [
            sender.immediate.single.rendered.text,
            sender.immediate.single.rendered.html,
          ]) {
            expect(part, contains('Alice'));
            expect(part, contains('Read this before Saturday'));
            expect(part, isNot(contains(blockedNote)));
          }
          await digest();
          expect(sender.digests, isEmpty);
        },
      );

      test(
        'a present recipient with push receives no immediate email',
        () async {
          await expectFirstEmail();
          await resetHistory();
          await UserPresenceRepository(database).update(
            _carol,
            status: UserPresenceStatus.online,
            lastSeenAt: DateTime.utc(2020),
            lastNotifiedAt: DateTime.utc(2020, 1, 1, 0, 0, 1),
          );
          await share();
          await deliver();
          expect(sender.immediate, hasLength(1));
        },
      );

      test(
        'a present recipient without push receives the noted Post by email',
        () async {
          await UserPresenceRepository(database).update(
            _carol,
            status: UserPresenceStatus.online,
            lastSeenAt: DateTime.utc(2020),
            lastNotifiedAt: DateTime.utc(2020, 1, 1, 0, 0, 1),
          );
          channels = BeaconNotificationService(
            queue!,
            _NoPostTokens(),
            remote,
            preferences,
            email,
            Logger('PostShareEmailTest'),
          );
          await expectFirstEmail();
        },
      );

      test(
        'an unnoted share remains digest-only while a noted share is immediate',
        () async {
          await expectFirstEmail();
          await resetHistory();
          await share(note: '   ');
          await deliver();
          expect(sender.immediate, hasLength(1));
          await digest();
          final carolDigests = sender.digests
              .where((e) => e.to == '$_carol@example.com')
              .toList();
          expect(carolDigests, hasLength(1));
          expect(
            carolDigests.single.rendered.text,
            contains('A neighbourhood story'),
          );
          expect(
            carolDigests.single.rendered.text,
            contains('/beacon/view/$_beacon'),
          );
        },
      );

      test(
        'disabling shared Post email suppresses immediate delivery and the digest',
        () async {
          await expectFirstEmail();
          final prefs = await preferences.getForAccount(_carol);
          // Check the category persisted for the real share, so opting out
          // exercises the Post setting rather than another email category.
          final receipts = await NotificationOutboxRepository(
            database,
          ).pendingForAccount(_carol);
          // Immediate delivery consumed that receipt, so read its persisted category.
          final rows = await writer.execute(
            Sql.named(
              'SELECT category FROM public.notification_outbox WHERE account_id = @account AND beacon_id = @beacon',
            ),
            parameters: {'account': _carol, 'beacon': _beacon},
          );
          final sharedCategory = rows.first.first as String;
          expect(
            sharedCategory,
            'postsSharedWithMe',
            reason:
                'The disabled setting must be the shared Post email category itself',
          );
          expect(
            sharedCategory,
            isNot('coordination'),
            reason:
                'Post email can be disabled independently of other coordination',
          );
          expect(
            prefs.emailCategories.map((c) => c.name),
            contains(sharedCategory),
          );
          expect(receipts, isEmpty);
          await resetHistory();
          await preferences.upsert(
            prefs.copyWith(
              emailCategories: {
                for (final c in prefs.emailCategories)
                  if (c.name != sharedCategory) c,
              },
            ),
          );
          await share();
          await share(from: _bob, note: '');
          await deliver();
          await digest();
          expect(sender.immediate, hasLength(1));
          expect(
            sender.digests.where((e) => e.to == '$_carol@example.com'),
            isEmpty,
          );
          final saved = await preferences.getForAccount(_carol);
          expect(
            saved.emailCategories.map((category) => category.name),
            contains('coordination'),
          );
          expect(
            saved.emailCategories.map((category) => category.name),
            isNot(contains(sharedCategory)),
          );
          // A real Request relay uses coordination, which the Post toggle
          // must leave enabled. Exercise its normal delivery and digest path.
          await harness.forwards.forward(
            senderId: _author,
            beaconId: _request,
            recipientIds: const [_carol],
            sharedNote: 'A Request still reaches you',
          );
          await deliver();
          await digest();
          expect(sender.immediate, hasLength(1));
          expect(
            sender.digests,
            hasLength(1),
            reason:
                'Opting out of Post email must not disable coordination email',
          );
          for (final part in [
            sender.digests.single.rendered.text,
            sender.digests.single.rendered.html,
          ]) {
            expect(part, contains('/beacon/view/$_request'));
            expect(part, contains('Alice'));
            expect(part, isNot(contains('/beacon/view/$_beacon')));
            expect(part, isNot(contains('Read this before Saturday')));
          }
        },
      );
    });

    group('a Post arrival', () {
      test('has a job that says a post was shared', () async {
        await publish();

        final jobs = await claimJobs();

        for (final recipient in [_bob, _carol]) {
          final job = forRecipient(jobs, recipient).single;
          expect(job.kind, NotificationKind.newRelay);
          expect(job.title, 'Alice');
          expect(job.body, 'Alice shared a post with you');
        }
      });

      test('is pushed with the Post copy', () async {
        await publish();
        final job = forRecipient(await claimJobs(), _bob).single;

        final sent = await pushed([job]);

        expect(sent.single.body, 'Alice shared a post with you');
      });

      test(
        'is pushed in Russian to a recipient whose locale is Russian',
        () async {
          await publish();
          final jobs = await claimJobs();

          final sent = await pushed(
            [forRecipient(jobs, _bob).single],
            locales: const {_bob: 'ru'},
          );

          expect(sent.single.body, 'Alice поделился постом с вами');
        },
      );

      test('two distinct arrivals in one window are pushed as one Post '
          'batch', () async {
        await publish();
        await forward(
          senderId: _bob,
          beaconId: _beacon,
          recipientIds: const [_carol],
        );
        final arrivals = forRecipient(await claimJobs(), _carol);
        expect(arrivals.map((job) => job.body), [
          'Alice shared a post with you',
          'Bob shared a post with you',
        ]);

        final sent = await pushed(arrivals);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 posts shared with you'));
      });
    });

    group('a first response to a Post', () {
      test('has a job that carries the responder text', () async {
        await publish();
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _bob,
          body: 'Count me in',
        );

        final job = forRecipient(await claimJobs(), _author).single;

        expect(job.kind, NotificationKind.postFirstResponse);
        expect(job.title, 'Bob');
        expect(job.body, 'Count me in');
      });

      test('two distinct responses in one window are pushed as one replies '
          'batch', () async {
        await publish();
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _bob,
          body: 'Count me in',
        );
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _carol,
          body: 'Me too',
        );
        final responses = forRecipient(await claimJobs(), _author);
        expect(responses.map((job) => job.body), ['Count me in', 'Me too']);

        final sent = await pushed(responses);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 replies to your posts'));
      });
    });

    group('a Request relay', () {
      test('has a job that says a request was forwarded', () async {
        await forward(
          senderId: _author,
          beaconId: _request,
          recipientIds: const [_bob],
        );

        final job = forRecipient(await claimJobs(), _bob).single;

        expect(job.kind, NotificationKind.newRelay);
        expect(job.body, 'Alice forwarded a request to you');
      });

      test('two distinct relays in one window keep the Request batch '
          'text', () async {
        await forward(
          senderId: _author,
          beaconId: _request,
          recipientIds: const [_bob, _carol],
        );
        await forward(
          senderId: _bob,
          beaconId: _request,
          recipientIds: const [_carol],
        );
        final arrivals = forRecipient(await claimJobs(), _carol);
        expect(arrivals.map((job) => job.body), [
          'Alice forwarded a request to you',
          'Bob forwarded a request to you',
        ]);

        final sent = await pushed(arrivals);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 requests forwarded to you'));
      });
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
    TRUNCATE TABLE public.attention_channel_delivery,
      public.attention_channel_throttle, public.post_first_response,
      public.notification_outbox,
      public.attention_occurrence_recipient, public.attention_occurrence,
      public.beacon, public."user" CASCADE
  ''');
  for (final id in _users) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES (@id, @name, @key)
      '''),
      parameters: {
        'id': id,
        'name': switch (id) {
          _author => 'Alice',
          _bob => 'Bob',
          _ => 'Carol',
        },
        'key': pgTestPublicKey('notif', _users.indexOf(id) + 1),
      },
    );
  }
  for (final (subject, object) in const [
    (_author, _bob),
    (_bob, _author),
    (_author, _carol),
    (_carol, _author),
    (_bob, _carol),
    (_carol, _bob),
  ]) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@subject, @object, 1)
      '''),
      parameters: {'subject': subject, 'object': object},
    );
  }
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable)
      VALUES (@beacon, @author, '', '', @draft, @kind, 1, false)
    '''),
    parameters: {
      'beacon': _beacon,
      'author': _author,
      'draft': _statusDraft,
      'kind': _kindPost,
    },
  );
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, published_at,
         is_discoverable)
      VALUES (@id, @author, 'Need a ladder', 'Borrow one', 0, 0, now(), true)
    '''),
    parameters: {'id': _request, 'author': _author},
  );
}

final class _RecordingRemote implements FcmRemoteRepositoryPort {
  final sent = <FcmNotificationEntity>[];

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    sent.add(message);
    return const [];
  }
}

final class _Tokens extends Fake implements FcmTokenRepositoryPort {
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

final class _Preferences extends Fake
    implements NotificationPreferenceRepositoryPort {
  _Preferences(this.locales);

  final Map<String, String> locales;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(
        accountId,
      ).copyWith(locale: locales[accountId] ?? 'en');

  @override
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now) async =>
      const {};
}

final class _SilentEmail extends Fake implements EmailNotificationPort {
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

final class _Harness {
  const _Harness(this.posts, this.room, this.forwards);

  final PostCase posts;
  final BeaconRoomCase room;
  final ForwardCase forwards;
}

_Harness _buildHarness(TenturaDb db, Env env) {
  final logger = Logger('PostNotificationPipelinePgTest');
  final uow = MutatingUnitOfWork(db);
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final beaconRepository = BeaconRepository(db);
  final roomRepository = BeaconRoomRepository(db);
  final help = HelpOfferRepository(db);
  final commitments = CommitmentRepository(db);
  final access = BeaconAccessRepository(db);
  final blocks = UserBlockRepository(env, db);
  final hierarchy = BeaconHierarchyRepository(db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      help,
      commitments,
    ),
    UserRepository(
      env,
      db,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    ),
    access,
    blocks,
  );
  final commitmentQuery = CommitmentQueryCase(
    commitments,
    help,
    env: env,
    logger: logger,
  );
  final images = _UnusedImages();
  final tasks = _Tasks();
  final beacons = BeaconCase(
    beaconRepository,
    images,
    _UnusedImageGc(),
    tasks,
    commitmentQuery,
    access,
    hierarchy,
    FakeBeaconChildCreatePort(),
    BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    ),
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
  final forwards = ForwardCase(
    ForwardEdgeRepository(db),
    ForwardAttributionRepository(db),
    help,
    InboxRepository(db),
    CapabilityEvidenceRepository(db),
    beaconRepository,
    blocks,
    PersonVisibilityRepository(db),
    access,
    attentionIntents: intents,
    attention: attention,
    postLock: PostLockRepository(db),
    env: env,
    logger: logger,
  );
  final room = BeaconRoomCase(
    roomRepository,
    CoordinationItemRepository(db),
    _UnusedFactCards(),
    images,
    tasks,
    _Storage(),
    _UnusedPolling(),
    _Quota(),
    blocks,
    uow,
    hierarchy,
    const ProductionDiscussionProductPolicy(),
    beaconRepository: beaconRepository,
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
  return _Harness(
    PostCase(
      beaconCase: beacons,
      forwardCase: forwards,
      roomCase: room,
      beaconRepository: beaconRepository,
      postLock: PostLockRepository(db),
      attention: attention,
    ),
    room,
    forwards,
  );
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

// Wait for the real email policy invoked by the channel service's unawaited
// handoff, rather than sleeping and racing an assertion against PostgreSQL.
final class _TrackedEmail extends Fake implements EmailNotificationPort {
  _TrackedEmail(this.delegate);
  final EmailNotificationService delegate;
  final pending = <Future<void>>[];

  Future<void> finish() async {
    await Future.wait(pending).timeout(const Duration(seconds: 10));
    pending.clear();
  }

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
  }) {
    final task = delegate.considerImmediate(
      recipientUserId: recipientUserId,
      kind: kind,
      beaconId: beaconId,
      channelCollapseKey: channelCollapseKey,
      title: title,
      body: body,
      actionUrl: actionUrl,
      pushDelivered: pushDelivered,
    );
    pending.add(task);
    return task;
  }

  @override
  Future<bool> considerImmediateByCategory({
    required String recipientUserId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required String categoryScope,
  }) {
    final task = delegate.considerImmediateByCategory(
      recipientUserId: recipientUserId,
      channelCollapseKey: channelCollapseKey,
      title: title,
      body: body,
      actionUrl: actionUrl,
      categoryScope: categoryScope,
    );
    pending.add(task.then((_) {}));
    return task;
  }
}

final class _PostContacts extends Fake
    implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      accountId == _carol ? '$accountId@example.com' : null;
}

typedef _PostEmail = ({String to, String locale, RenderedEmail rendered});

final class _PostEmailSender extends Fake implements EmailSenderPort {
  final immediate = <_PostEmail>[];
  final digests = <_PostEmail>[];
  Future<void> Function()? beforeNotificationCompletes;

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    immediate.add((
      to: to,
      locale: locale,
      rendered: const EmailTemplateRenderer().renderNotification(
        content: content,
        locale: locale,
      ),
    ));
    await beforeNotificationCompletes?.call();
  }

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    digests.add((
      to: to,
      locale: locale,
      rendered: const EmailTemplateRenderer().renderDigest(
        content: content,
        locale: locale,
      ),
    ));
  }
}

final class _NoPostTokens extends Fake implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      const [];
}
