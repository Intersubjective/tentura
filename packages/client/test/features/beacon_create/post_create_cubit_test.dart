// A Post is created by writing its first message. `BeaconCreateCubit` in Post
// mode keeps a server draft for a stable id, then publishes everything in one
// `postPublish` call (first attachment inline, mentions as parallel lists) and
// uploads the remaining attachments into the root message afterwards. A lost
// response is retried with the same arguments; a failed upload retries only
// that upload and never re-sends `postPublish`.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/entity/committed_mention.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

/// One `postPublish` call, as the port received it.
@immutable
class _PublishCall {
  const _PublishCall({
    required this.beaconId,
    required this.body,
    required this.mentionUserIds,
    required this.mentionOffsets,
    required this.mentionLengths,
    required this.recipientIds,
    required this.notes,
    required this.forwardPolicy,
    required this.attachmentName,
  });

  final String beaconId;
  final String body;
  final List<String> mentionUserIds;
  final List<int> mentionOffsets;
  final List<int> mentionLengths;
  final Set<String> recipientIds;
  final Map<String, String> notes;
  final BeaconForwardPolicyValue forwardPolicy;
  final String? attachmentName;

  @override
  bool operator ==(Object other) =>
      other is _PublishCall &&
      beaconId == other.beaconId &&
      body == other.body &&
      _listEq(mentionUserIds, other.mentionUserIds) &&
      _listEq(mentionOffsets, other.mentionOffsets) &&
      _listEq(mentionLengths, other.mentionLengths) &&
      _setEq(recipientIds, other.recipientIds) &&
      _mapEq(notes, other.notes) &&
      forwardPolicy == other.forwardPolicy &&
      attachmentName == other.attachmentName;

  @override
  int get hashCode => Object.hash(beaconId, body, attachmentName);

  @override
  String toString() =>
      '_PublishCall($beaconId, "$body", ${mentionUserIds.join(',')}, '
      '$mentionOffsets, $mentionLengths, $recipientIds, $notes, '
      '${forwardPolicy.name}, $attachmentName)';
}

bool _listEq<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every(
      (i) => a[i] == b[i],
    );

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

bool _mapEq(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

class _FakePostPublishPort implements PostPublishPort {
  /// Everything that reached the server, in order: `publish` and
  /// `attach:<fileName>`.
  final events = <String>[];
  final publishCalls = <_PublishCall>[];
  final attachCalls = <({String beaconId, String messageId, String name})>[];

  /// Errors thrown by successive `postPublish` calls; null/absent = success.
  final publishErrors = <Exception?>[];

  /// File names whose next upload fails once.
  final failUploadOnce = <String>{};

  @override
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? attachment,
  }) async {
    events.add('publish');
    publishCalls.add(
      _PublishCall(
        beaconId: beaconId,
        body: body,
        mentionUserIds: mentionUserIds,
        mentionOffsets: mentionOffsets,
        mentionLengths: mentionLengths,
        recipientIds: recipientIds.toSet(),
        notes: notes,
        forwardPolicy: forwardPolicy,
        attachmentName: attachment?.fileName,
      ),
    );
    final index = publishCalls.length - 1;
    if (index < publishErrors.length && publishErrors[index] != null) {
      throw publishErrors[index]!;
    }
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-msg-1');
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    events.add('attach:${upload.fileName}');
    attachCalls.add((
      beaconId: beaconId,
      messageId: messageId,
      name: upload.fileName,
    ));
    if (failUploadOnce.remove(upload.fileName)) {
      throw Exception('upload of ${upload.fileName} failed');
    }
  }
}

RoomPendingUpload _file(String name) => RoomPendingUpload(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  fileName: name,
  mimeType: 'image/png',
);

ForwardCubit _forwardCubit(
  FakeUiEffectPort effects, {
  Set<String> selected = const {'Umaria', 'Uoleg'},
  Map<String, String> notes = const {'Umaria': 'ты же хотел'},
}) => ForwardCubit(
  beaconId: 'server-beacon',
  embedded: true,
  effects: effects,
  debugSkipInitialLoad: true,
  debugInitialState: ForwardState(
    beaconId: 'server-beacon',
    selectedIds: selected,
    perRecipientNotes: notes,
  ),
);

void main() {
  late FakeBeaconWritePort write;
  late _FakePostPublishPort port;
  late FakeUiEffectPort effects;
  late BeaconCreateCubit cubit;
  late ForwardCubit forward;

  setUp(() {
    write = FakeBeaconWritePort();
    port = _FakePostPublishPort();
    effects = FakeUiEffectPort();
    cubit = BeaconCreateCubit(
      kind: BeaconKind.post,
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      postPublishCase: PostPublishCase(port),
      effects: effects,
    );
    forward = _forwardCubit(effects);
  });

  tearDown(() async {
    await cubit.close();
    await forward.close();
  });

  Future<bool> publish({
    String body = 'Кто в субботу на велопрогулку?',
    List<CommittedMention> mentions = const [],
    BeaconForwardPolicyValue policy = BeaconForwardPolicyValue.open,
    List<RoomPendingUpload> attachments = const [],
  }) => cubit.publishPost(
    body: body,
    mentions: mentions,
    forwardCubit: forward,
    forwardPolicy: policy,
    attachments: attachments,
  );

  group('Post draft', () {
    test('is created as a Post with no title and not discoverable', () async {
      final id = await cubit.ensureDraft(context: '', showMessage: false);

      expect(id, 'server-beacon');
      final sent = write.createdFields.single;
      expect(sent.kind, BeaconKind.post);
      expect(sent.title, isEmpty, reason: 'not the "Draft" substitute');
      expect(sent.isDiscoverable, isFalse);
      expect(
        sent.forwardPolicy,
        BeaconForwardPolicyValue.open,
        reason: 'forwarding is allowed by default («Можно пересылать» on)',
      );
    });

    test(
      'a Request cubit still creates a Request with the draft title',
      () async {
        final requestCubit = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          effects: effects,
        );
        addTearDown(requestCubit.close);

        await requestCubit.ensureDraft(context: '', showMessage: false);

        final sent = write.createdFields.single;
        expect(sent.kind, BeaconKind.request);
        expect(sent.title, 'Draft');
      },
    );
  });

  group('publishPost', () {
    test(
      'calls postPublish once with recipients, notes, policy and body',
      () async {
        final sent = await publish(policy: BeaconForwardPolicyValue.closed);

        expect(sent, isTrue);
        expect(port.publishCalls, hasLength(1));
        final call = port.publishCalls.single;
        expect(call.beaconId, 'server-beacon');
        expect(call.body, 'Кто в субботу на велопрогулку?');
        expect(call.recipientIds, {'Umaria', 'Uoleg'});
        expect(call.notes, {'Umaria': 'ты же хотел'});
        expect(call.forwardPolicy, BeaconForwardPolicyValue.closed);
        expect(call.attachmentName, isNull);
        expect(port.attachCalls, isEmpty);
      },
    );

    test('creates the Post draft first when none exists yet', () async {
      await publish();

      expect(write.createdFields, hasLength(1));
      expect(write.createdFields.single.kind, BeaconKind.post);
      expect(port.publishCalls.single.beaconId, 'server-beacon');
    });

    test(
      'maps committed mentions to parallel id, offset and length lists',
      () async {
        await publish(
          body: 'Привет @Мария и @Олег',
          mentions: const [
            (userId: 'Umaria', start: 7, end: 13),
            (userId: 'Uoleg', start: 16, end: 21),
          ],
        );

        final call = port.publishCalls.single;
        expect(call.mentionUserIds, ['Umaria', 'Uoleg']);
        expect(call.mentionOffsets, [7, 16]);
        expect(call.mentionLengths, [6, 5]);
      },
    );

    test(
      'sends the first attachment inline and uploads the rest after publish',
      () async {
        final sent = await publish(
          attachments: [_file('a.png'), _file('b.png'), _file('c.png')],
        );

        expect(sent, isTrue);
        expect(port.publishCalls, hasLength(1));
        expect(port.publishCalls.single.attachmentName, 'a.png');
        expect(port.events, ['publish', 'attach:b.png', 'attach:c.png']);
        expect(
          port.attachCalls.map((c) => (c.beaconId, c.messageId)).toSet(),
          {('server-beacon', 'root-msg-1')},
          reason: 'uploads go into the root message returned by postPublish',
        );
      },
    );

    test(
      'a failed upload retries only that upload, never postPublish',
      () async {
        port.failUploadOnce.add('c.png');
        final attachments = [_file('a.png'), _file('b.png'), _file('c.png')];

        final first = await publish(attachments: attachments);
        expect(first, isFalse);
        expect(port.publishCalls, hasLength(1));

        final retry = await publish(attachments: attachments);

        expect(retry, isTrue);
        expect(
          port.publishCalls,
          hasLength(1),
          reason: 'postPublish is not re-sent',
        );
        expect(
          port.attachCalls.map((c) => c.name),
          ['b.png', 'c.png', 'c.png'],
          reason:
              'b.png was uploaded; only c.png is retried; a.png rode inline',
        );
        expect(write.createdFields, hasLength(1));
      },
    );

    test('a failed upload surfaces the error to the user', () async {
      port.failUploadOnce.add('b.png');

      await publish(attachments: [_file('a.png'), _file('b.png')]);

      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });

    test(
      'a network error on postPublish can be retried with identical arguments',
      () async {
        port.publishErrors.add(Exception('network down'));
        final attachments = [_file('a.png'), _file('b.png')];
        const mentions = [(userId: 'Umaria', start: 0, end: 6)];

        final first = await publish(
          body: '@Мария привет',
          mentions: mentions,
          attachments: attachments,
        );
        expect(first, isFalse);
        expect(
          port.attachCalls,
          isEmpty,
          reason: 'nothing is uploaded before the root message exists',
        );
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);

        final retry = await publish(
          body: '@Мария привет',
          mentions: mentions,
          attachments: attachments,
        );

        expect(retry, isTrue);
        expect(port.publishCalls, hasLength(2));
        expect(port.publishCalls[1], port.publishCalls[0]);
        expect(port.attachCalls.map((c) => c.name), ['b.png']);
        expect(
          write.createdFields,
          hasLength(1),
          reason: 'same draft is reused',
        );
      },
    );

    test('publishes an attachment-only Post with an empty body', () async {
      final sent = await publish(
        body: '',
        attachments: [_file('a.png'), _file('b.png')],
      );

      expect(sent, isTrue);
      expect(port.publishCalls, hasLength(1));
      expect(port.publishCalls.single.body, isEmpty);
      expect(port.publishCalls.single.attachmentName, 'a.png');
      expect(port.events, ['publish', 'attach:b.png']);
    });

    test(
      'publishes a single-photo Post inline with no follow-up upload',
      () async {
        final sent = await publish(body: '   ', attachments: [_file('a.png')]);

        expect(sent, isTrue);
        expect(port.publishCalls.single.attachmentName, 'a.png');
        expect(port.attachCalls, isEmpty);
      },
    );

    test('refuses to publish with neither text nor attachment', () async {
      final sent = await publish(body: '  \n ');

      expect(sent, isFalse);
      expect(port.publishCalls, isEmpty);
      expect(
        write.createdFields,
        isEmpty,
        reason: 'no draft is created either',
      );
    });

    test(
      'publishes without recipients — visible only to the author',
      () async {
        final nobody = _forwardCubit(
          effects,
          selected: const {},
          notes: const {},
        );
        addTearDown(nobody.close);

        final sent = await cubit.publishPost(
          body: 'Кто в субботу на велопрогулку?',
          mentions: const [],
          forwardCubit: nobody,
          forwardPolicy: BeaconForwardPolicyValue.open,
          attachments: [_file('a.png')],
        );

        expect(sent, isTrue);
        expect(port.publishCalls.single.recipientIds, isEmpty);
      },
    );

    test('a failed publish leaves the draft and the composer usable', () async {
      port.publishErrors.add(Exception('network down'));

      final sent = await publish();

      expect(sent, isFalse);
      expect(cubit.state.isLive, isFalse);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.draftId, 'server-beacon');
      expect(write.deletedIds, isEmpty);
    });

    test('a successful publish turns the composer into a live Post', () async {
      await publish();

      expect(cubit.state.isLive, isTrue);
      expect(cubit.state.draftId, 'server-beacon');
    });
  });
}
