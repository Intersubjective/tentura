import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

// «You took it» when the baton was taken together, seen through the real
// delivery path (the email digest): the identity port decides what the
// recipient may see of the co-taker. A visible co-taker is named; a hidden or
// blocked one gets exactly the solo copy and is never named anywhere.

/// What the recipient may see of each user id; unknown ids are visible
/// without a name.
class _PeopleIdentity implements NotificationIdentityPort {
  const _PeopleIdentity(this.visibleNames, {this.hidden = const {}});

  final Map<String, String> visibleNames;
  final Set<String> hidden;

  @override
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> requests,
  ) async => [
    for (final r in requests)
      NotificationIdentity(
        entityKind: NotificationEntityKind.request,
        label: 'Fix the roof',
        tombstone: false,
        readable: true,
        actorName: hidden.contains(r.actorId) ? null : visibleNames[r.actorId],
        actorHidden: hidden.contains(r.actorId),
        relatedLabel: null,
        expired: false,
      ),
  ];
}

class _Prefs implements NotificationPreferenceRepositoryPort {
  _Prefs(this._p);
  final NotificationPreferencesEntity _p;
  @override
  Future<NotificationPreferencesEntity> getForAccount(String id) async => _p;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Outbox implements NotificationOutboxRepositoryPort {
  _Outbox(this._pending);
  final List<NotificationOutboxItemEntity> _pending;
  @override
  Future<List<String>> accountsWithPendingEmail() async => ['u1'];
  @override
  Future<DateTime?> lastEmailedAt(String accountId) async => null;
  @override
  Future<List<NotificationOutboxItemEntity>> pendingForAccount(
    String accountId,
  ) async => _pending;
  @override
  Future<int> markEmailed(List<String> ids) async => ids.length;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Contacts implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      'u1@example.com';
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Email implements EmailSenderPort {
  EmailDigestContent? digest;
  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async => digest = content;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  final env = Env(
    environment: Environment.test,
    publicOrigin: 'https://t.example',
    unsubscribeSigningSecret: 'secret',
  );
  final now = DateTime.utc(2026, 6, 24, 8, 30);

  /// Every text the digest shows for one pair `baton_taken` receipt.
  Future<List<String>> shown({
    required String locale,
    required NotificationIdentityPort identity,
    bool withCoTaker = true,
  }) async {
    final sender = _Email();
    await EmailDigestCase(
      _Prefs(
        NotificationPreferencesEntity(
          accountId: 'u1',
          emailCategories: const {NotificationCategory.coordination},
          locale: locale,
        ),
      ),
      _Outbox([
        NotificationOutboxItemEntity(
          id: 'taken',
          accountId: 'u1',
          category: NotificationCategory.coordination,
          kind: NotificationKind.batonTaken,
          priority: NotificationPriority.high,
          title: 't',
          body: 'b',
          actionUrl: '/#/x',
          createdAt: now,
          collapsedCount: 1,
          beaconId: 'b1',
          presentationKey: 'baton_taken',
          presentationPayload: {
            'excerpt': 'hello',
            if (withCoTaker) 'withUserId': 'co-1',
          },
        ),
      ]),
      _Contacts(),
      sender,
      EmailLinkBuilder(env),
      env,
      Logger('test'),
      identity: identity,
    ).runDue(now: now);
    final digest = sender.digest;
    expect(digest, isNotNull, reason: 'the digest was sent');
    final lines = <String>[];
    for (final section in digest!.sections) {
      for (final entry in section.entries) {
        if (entry is EmailDigestGroup) {
          lines
            ..add(entry.label)
            ..addAll(entry.lines);
        } else if (entry is EmailDigestLine) {
          lines.add(entry.text);
        }
      }
    }
    return lines;
  }

  const visible = _PeopleIdentity({'co-1': 'Boris'});

  test('English names the visible co-taker', () async {
    final out = await shown(locale: 'en', identity: visible);
    expect(out.join(' '), contains('You and Boris took it: hello'));
  });

  test('Russian names the visible co-taker without «с»', () async {
    final out = (await shown(locale: 'ru', identity: visible)).join(' ');
    expect(out, contains('Вы и Boris взялись: hello'));
    expect(out, isNot(matches(RegExp('с [A-ZА-ЯЁ]'))));
  });

  for (final (why, identity) in [
    ('hidden', const _PeopleIdentity({}, hidden: {'co-1'})),
    ('blocked', const _PeopleIdentity({'co-1': 'Boris'}, hidden: {'co-1'})),
  ]) {
    test('a $why co-taker gets the solo copy and is never named', () async {
      final en = (await shown(locale: 'en', identity: identity)).join(' ');
      expect(en, contains('You took it: hello'));
      expect(en, isNot(contains('Boris')));
      expect(en, isNot(contains(' and ')));
      final ru = (await shown(locale: 'ru', identity: identity)).join(' ');
      expect(ru, contains('Вы взялись: hello'));
      expect(ru, isNot(contains('Boris')));
    });
  }

  test('a receipt without withUserId renders the solo copy', () async {
    final out = (await shown(
      locale: 'en',
      identity: visible,
      withCoTaker: false,
    )).join(' ');
    expect(out, contains('You took it: hello'));
    expect(out, isNot(contains('Boris')));
  });
}
