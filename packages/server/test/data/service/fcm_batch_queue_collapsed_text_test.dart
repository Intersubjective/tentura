import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';

/// What a reader's device finally gets when several pushes about one Request
/// coalesce: the Request label stays the title and the count is localized.
void main() {
  late _Remote remote;
  late FcmBatchQueue queue;

  setUp(() {
    remote = _Remote();
    queue = FcmBatchQueue(remote, Logger('FcmBatchQueueCollapsedTextTest'));
  });
  tearDown(() => queue.dispose());

  /// Enqueues [kinds] for one receiver and Request, and returns the single
  /// message the transport receives after the flush.
  Future<FcmNotificationEntity> collapse(
    List<NotificationKind> kinds, {
    required String locale,
    required String sentence,
    String? label = 'Fix the roof',
  }) async {
    for (final kind in kinds) {
      queue.enqueue(
        receiverId: 'Ureader',
        fcmTokens: {'token-reader'},
        message: FcmNotificationEntity(
          title: 'STORED-$kind',
          body: 'STORED-BODY',
          beaconId: 'Brequest',
          kind: kind,
          priority: NotificationPriority.normal,
          entityLabel: label,
          eventSentence: sentence,
          locale: locale,
        ),
      );
    }
    final deadline = DateTime.timestamp().add(const Duration(seconds: 4));
    while (remote.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // A second flush of the same batch must not follow.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(remote.sent, hasLength(1));
    return remote.sent.single;
  }

  const mixed = [
    NotificationKind.commitmentEvent,
    NotificationKind.coordinationChanged,
  ];

  test('English batch keeps the Request label as title', () async {
    final sent = await collapse(
      mixed,
      locale: 'en',
      sentence: 'Anna offered help',
    );
    expect(sent.title, 'Fix the roof');
    expect(sent.body, '2 updates · latest: Anna offered help');
  });

  test('Russian batch is localized with the right plural', () async {
    final sent = await collapse(
      mixed,
      locale: 'ru',
      sentence: 'Анна предлагает помощь',
    );
    expect(sent.title, 'Fix the roof');
    expect(sent.body, '2 обновления · последнее: Анна предлагает помощь');
  });

  for (final (count, word) in [
    (5, '5 обновлений'),
    (21, '21 обновление'),
    (22, '22 обновления'),
  ]) {
    test('Russian count $count reads «$word»', () async {
      final sent = await collapse(
        [
          for (var i = 0; i < count; i++)
            if (i.isEven)
              NotificationKind.commitmentEvent
            else
              NotificationKind.coordinationChanged,
        ],
        locale: 'ru',
        sentence: 'Анна предлагает помощь',
      );
      expect(sent.body, '$word · последнее: Анна предлагает помощь');
    });
  }

  test('without a readable label the title is the app name and the body is '
      'only the count', () async {
    final en = await collapse(
      mixed,
      locale: 'en',
      sentence: 'Anna offered help',
      label: null,
    );
    expect(en.title, 'Tentura');
    expect(en.body, '2 updates');
    expect(en.body, isNot(contains('Fix the roof')));

    remote.sent.clear();
    final ru = await collapse(
      mixed,
      locale: 'ru',
      sentence: 'Анна предлагает помощь',
      label: null,
    );
    expect(ru.title, 'Tentura');
    expect(ru.body, '2 обновления');
  });
}

final class _Remote implements FcmRemoteRepositoryPort {
  final sent = <FcmNotificationEntity>[];

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    sent.add(message);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
