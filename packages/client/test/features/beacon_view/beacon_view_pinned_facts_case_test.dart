import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_already_pinned_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_pin_after_message_exception.dart';

import 'beacon_view_case_test_support.dart';

BeaconFactCard _fact({
  required String id,
  required DateTime createdAt,
  DateTime? updatedAt,
}) =>
    BeaconFactCard(
      id: id,
      beaconId: 'b1',
      factText: id,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'other',
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: BeaconFactCardStatusBits.active,
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  test('watermark keys are per user and beacon', () {
    final case_ = buildTestBeaconViewCase();
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'a', createdAt: t0)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u2',
      facts: [_fact(id: 'b', createdAt: t1)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b2',
      userId: 'u1',
      facts: [_fact(id: 'c', createdAt: t1)],
    );

    expect(case_.pinnedFactsSeenAt('b1', 'u1'), t0);
    expect(case_.pinnedFactsSeenAt('b1', 'u2'), t1);
    expect(case_.pinnedFactsSeenAt('b2', 'u1'), t1);
  });

  test('first baseline is sticky', () {
    final case_ = buildTestBeaconViewCase();
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'a', createdAt: t0)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'b', createdAt: t1)],
    );
    expect(case_.pinnedFactsSeenAt('b1', 'u1'), t0);
  });

  test('mark seen uses max fact timestamp, not wall clock', () {
    final case_ = buildTestBeaconViewCase();
    final before = DateTime.now().toUtc();
    case_.markPinnedFactsSeen(
      beaconId: 'b1',
      userId: 'u1',
      facts: [
        _fact(id: 'a', createdAt: t0),
        _fact(id: 'b', createdAt: t0, updatedAt: t1),
      ],
    );
    final seen = case_.pinnedFactsSeenAt('b1', 'u1');
    expect(seen, t1);
    expect(seen!.isBefore(before) || seen.isAtSameMomentAs(t1), isTrue);
  });

  test('empty facts mark epoch', () {
    final case_ = buildTestBeaconViewCase();
    case_.markPinnedFactsSeen(
      beaconId: 'b1',
      userId: 'u1',
      facts: const [],
    );
    expect(case_.pinnedFactsSeenAt('b1', 'u1'), epoch);
  });

  test('pinFactFromComposer posts General then pins with source id', () async {
    final facts = FakeBeaconViewFactCardRepository();
    final room = FakeBeaconViewRoomRepository();
    final case_ = buildTestBeaconViewCase(
      factCardsRepo: facts,
      roomRepo: room,
    );

    await case_.pinFactFromComposer(
      beaconId: 'b1',
      messageBody: 'note',
      factText: 'note',
      visibility: BeaconFactCardVisibilityBits.public,
    );

    expect(room.createdMessages, hasLength(1));
    expect(room.createdMessages.single.threadItemId, isNull);
    expect(room.createdMessages.single.body, 'note');
    expect(facts.pins, hasLength(1));
    expect(facts.pins.single.sourceMessageId, 'Mcreated01');
    expect(facts.pins.single.factText, 'note');
  });

  test('pinFactFromComposer attachment-only keeps empty message body', () async {
    final facts = FakeBeaconViewFactCardRepository();
    final room = FakeBeaconViewRoomRepository();
    final case_ = buildTestBeaconViewCase(
      factCardsRepo: facts,
      roomRepo: room,
    );
    final upload = RoomPendingUpload(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'shot.png',
      mimeType: 'image/png',
    );

    await case_.pinFactFromComposer(
      beaconId: 'b1',
      messageBody: '',
      factText: 'shot.png',
      visibility: BeaconFactCardVisibilityBits.room,
      uploads: [upload],
    );

    expect(room.createdMessages.single.body, '');
    expect(room.createdMessages.single.firstAttachment, upload);
    expect(facts.pins.single.factText, 'shot.png');
    expect(facts.pins.single.visibility, BeaconFactCardVisibilityBits.room);
  });

  test('pinFactFromComposer pin failure keeps the created message', () async {
    final facts = FakeBeaconViewFactCardRepository()
      ..pinError = StateError('pin failed');
    final room = FakeBeaconViewRoomRepository();
    final case_ = buildTestBeaconViewCase(
      factCardsRepo: facts,
      roomRepo: room,
    );

    await expectLater(
      case_.pinFactFromComposer(
        beaconId: 'b1',
        messageBody: 'note',
        factText: 'note',
        visibility: BeaconFactCardVisibilityBits.public,
      ),
      throwsA(isA<BeaconFactPinAfterMessageException>()),
    );
    expect(room.createdMessages, hasLength(1));
    expect(facts.pins, isEmpty);
  });

  // #759: a retry after a failed pin pins the message already posted.
  test(
    'pinFactFromComposer pins a posted message without posting again',
    () async {
      final facts = FakeBeaconViewFactCardRepository();
      final room = FakeBeaconViewRoomRepository()..nextMessageId = 'Rsecond01';
      final case_ = buildTestBeaconViewCase(
        factCardsRepo: facts,
        roomRepo: room,
      );

      await case_.pinFactFromComposer(
        beaconId: 'b1',
        messageBody: 'note',
        factText: 'note',
        visibility: BeaconFactCardVisibilityBits.room,
        postedMessageId: 'Rposted01',
      );

      expect(room.createdMessages, isEmpty);
      expect(facts.pins.single.sourceMessageId, 'Rposted01');
      expect(facts.pins.single.visibility, BeaconFactCardVisibilityBits.room);
    },
  );

  test(
    'pinFactFromComposer tries the pin again when the server is busy',
    () async {
      final facts = FakeBeaconViewFactCardRepository()
        ..pinErrorsOnce.add(const RemoteApiRetryLaterException(Duration.zero));
      final room = FakeBeaconViewRoomRepository();
      final case_ = buildTestBeaconViewCase(
        factCardsRepo: facts,
        roomRepo: room,
      );

      await case_.pinFactFromComposer(
        beaconId: 'b1',
        messageBody: 'note',
        factText: 'note',
        visibility: BeaconFactCardVisibilityBits.public,
      );

      expect(room.createdMessages, hasLength(1));
      expect(facts.pinCalls, 2);
      expect(facts.pins.single.sourceMessageId, 'Mcreated01');
    },
  );

  test('pinFactFromComposer gives up on a server that stays busy', () async {
    final facts = FakeBeaconViewFactCardRepository()
      ..pinError = const RemoteApiRetryLaterException(Duration.zero);
    final room = FakeBeaconViewRoomRepository();
    final case_ = buildTestBeaconViewCase(
      factCardsRepo: facts,
      roomRepo: room,
    );

    await expectLater(
      case_.pinFactFromComposer(
        beaconId: 'b1',
        messageBody: 'note',
        factText: 'note',
        visibility: BeaconFactCardVisibilityBits.public,
      ),
      throwsA(
        isA<BeaconFactPinAfterMessageException>().having(
          (e) => e.messageId,
          'messageId',
          'Mcreated01',
        ),
      ),
    );
    expect(facts.pinCalls, 3);
    expect(room.createdMessages, hasLength(1));
  });

  test(
    'pinFactFromComposer counts a fact already on the posted message as pinned',
    () async {
      final facts = FakeBeaconViewFactCardRepository()
        ..pinError = const BeaconFactAlreadyPinnedException(factCardId: 'F1');
      final room = FakeBeaconViewRoomRepository();
      final case_ = buildTestBeaconViewCase(
        factCardsRepo: facts,
        roomRepo: room,
      );

      await case_.pinFactFromComposer(
        beaconId: 'b1',
        messageBody: 'note',
        factText: 'note',
        visibility: BeaconFactCardVisibilityBits.public,
        postedMessageId: 'Rposted01',
      );

      expect(room.createdMessages, isEmpty);
    },
  );
}
