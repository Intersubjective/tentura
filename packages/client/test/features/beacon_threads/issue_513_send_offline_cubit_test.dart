import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// #513: a send that fails because the browser is offline must leave a
/// visible "not sent" state the composer can show (with Retry), instead of
/// only a snackbar. A refusal from the server is not "offline".
void main() {
  group('issue #513 RoomCubit.sendMessage offline state', () {
    test('a connectivity failure marks the send as not sent offline', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(cubit.state.sendFailedOffline, isFalse);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(fakeRoom.createMessageCalls, 1);
      expect(cubit.state.sendFailedOffline, isTrue);
    });

    test(
      'an unmapped timeout stays an ordinary error (the client link always '
      'maps it; see the mapped case below)',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom =
            FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
              ..createMessageError = TimeoutException(
                'GraphQL request timed out',
                const Duration(seconds: 1),
              );
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(fakeRoom, effects: effects);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(fakeRoom.createMessageCalls, 1);
        expect(cubit.state.sendFailedOffline, isFalse);
        expect(effects.emitted, isNotEmpty);
      },
    );

    // #654: the send carries an idempotency key, so a timeout (the message
    // may be saved) gets «Not confirmed» with Retry; Retry sends the same
    // key and the server hands back the saved message.
    test(
      'a timeout as the client link delivers it (mapped) is unconfirmed, not '
      'offline, and shows Retry instead of an error',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom =
            FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
              ..createMessageError = mapRemoteFailure(
                TimeoutException(
                  'GraphQL request timed out',
                  const Duration(seconds: 15),
                ),
              );
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(fakeRoom, effects: effects);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(fakeRoom.createMessageCalls, 1);
        expect(cubit.state.sendFailedOffline, isFalse);
        expect(cubit.state.sendUnconfirmed, isTrue);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);

        fakeRoom.createMessageError = null;
        expect(await cubit.sendMessage(body: 'see you at 6'), isTrue);

        expect(cubit.state.sendUnconfirmed, isFalse);
        expect(fakeRoom.clientMessageIds, hasLength(2));
        expect(fakeRoom.clientMessageIds.first, isNotNull);
        expect(
          fakeRoom.clientMessageIds.last,
          fakeRoom.clientMessageIds.first,
          reason: 'Retry reuses the key, so the server cannot save it twice',
        );
      },
    );

    test('a retry after offline reuses the key; a new message gets a new '
        'one', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: 'see you at 6'), isTrue);
      expect(await cubit.sendMessage(body: 'see you at 6'), isTrue);

      final keys = fakeRoom.clientMessageIds;
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(
        keys[2],
        isNot(keys[0]),
        reason: 'the same text sent again after a success is a new message',
      );
    });

    RoomPendingUpload photo(String name) => RoomPendingUpload(
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      fileName: name,
      mimeType: 'image/jpeg',
    );

    // Codex review of #654: a file picked again is a new send even when its
    // name and size match the failed one.
    test(
      'a re-picked file with the same name and size gets a new key',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..createMessageError = const ConnectionUplinkException();
        final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final first = photo('van.jpg');
        expect(await cubit.sendMessage(body: 'van', uploads: [first]), isFalse);
        expect(await cubit.sendMessage(body: 'van', uploads: [first]), isFalse);
        fakeRoom.createMessageError = null;
        expect(
          await cubit.sendMessage(body: 'van', uploads: [photo('van.jpg')]),
          isTrue,
        );

        final keys = fakeRoom.clientMessageIds;
        expect(keys[1], keys[0], reason: 'Retry keeps the same upload objects');
        expect(keys[2], isNot(keys[0]));
      },
    );

    // Codex review of #654: extra attachments are added one call each after
    // the message; a retry adds only those the saved message lacks.
    test(
      'a retry adds only the extra attachments the saved message lacks',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom =
            FakeBeaconThreadsRepository(
                userId: kRoomCubitFakeMyUserId,
              )
              ..createMessageError = mapRemoteFailure(
                TimeoutException('GraphQL request timed out'),
              );
        final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        final uploads = [photo('a.jpg'), photo('b.jpg'), photo('c.jpg')];

        expect(await cubit.sendMessage(body: 'van', uploads: uploads), isFalse);
        expect(fakeRoom.addAttachmentCalls, 0);

        // The timed-out send was saved with a.jpg and b.jpg.
        fakeRoom
          ..createMessageError = null
          ..fetchMessageTargetsById['msg-created'] = RoomMessage(
            id: 'msg-created',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: kRoomCubitFakeMyUserId,
            body: 'van',
            createdAt: DateTime.utc(2026, 10, 23),
            attachments: [
              for (var i = 0; i < 2; i++)
                RoomMessageAttachment(
                  id: 'att-$i',
                  kind: 1,
                  position: i,
                  mime: 'image/jpeg',
                  sizeBytes: 4,
                ),
            ],
          );
        expect(await cubit.sendMessage(body: 'van', uploads: uploads), isTrue);

        expect(fakeRoom.addAttachmentCalls, 1, reason: 'only c.jpg is missing');
      },
    );

    // Codex review round 2: the message can be saved while a later step
    // fails with an ordinary error; the next Send must not post it again.
    test('a retry whose attachment read-back fails keeps the key', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      final uploads = [photo('a.jpg'), photo('b.jpg')];

      expect(await cubit.sendMessage(body: 'van', uploads: uploads), isFalse);
      fakeRoom
        ..createMessageError = null
        ..fetchMessageTargetError = const RemoteApiException(
          'Room access required',
          code: '1003',
        );
      expect(await cubit.sendMessage(body: 'van', uploads: uploads), isFalse);
      fakeRoom.fetchMessageTargetError = null;
      expect(await cubit.sendMessage(body: 'van', uploads: uploads), isTrue);

      final keys = fakeRoom.clientMessageIds;
      expect(keys, hasLength(3));
      expect(keys.toSet(), hasLength(1));
    });

    test('a first send adds every extra attachment', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(
        await cubit.sendMessage(
          body: 'van',
          uploads: [photo('a.jpg'), photo('b.jpg'), photo('c.jpg')],
        ),
        isTrue,
      );

      expect(fakeRoom.addAttachmentCalls, 2);
    });

    test('editing the text after a failure sends it with a new key', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: 'see you at 7'), isTrue);

      expect(fakeRoom.clientMessageIds[1], isNot(fakeRoom.clientMessageIds[0]));
    });

    test('a server refusal is not reported as offline', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom =
          FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
            ..createMessageError = const RemoteApiException(
              'Discussion is closed',
              code: '1501',
            );
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(cubit.state.sendFailedOffline, isFalse);
      // Today's behaviour for a refusal stays: the error is still surfaced.
      expect(effects.emitted, isNotEmpty);
    });

    test('the next successful send clears the not sent state', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
      expect(cubit.state.sendFailedOffline, isTrue);

      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: 'see you at 6'), isTrue);

      expect(fakeRoom.createMessageCalls, 2);
      expect(cubit.state.sendFailedOffline, isFalse);
    });

    test(
      'a refusal after an offline failure clears the offline state',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..createMessageError = const ConnectionUplinkException();
        final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
        expect(cubit.state.sendFailedOffline, isTrue);

        fakeRoom.createMessageError = const RemoteApiException(
          'Discussion is closed',
          code: '1501',
        );
        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(cubit.state.sendFailedOffline, isFalse);
      },
    );
  });
}
