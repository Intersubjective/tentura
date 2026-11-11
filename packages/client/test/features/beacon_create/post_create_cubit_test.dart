// A Post is created by writing its first message. `BeaconCreateCubit` in Post
// mode keeps a server draft for a stable id, then publishes everything in one
// `postPublish` call (mentions as parallel lists). Attachments are already
// saved on the server draft, so publishing uploads none. A lost response is
// retried with the same arguments; a published Post is not published again.

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
  });

  final String beaconId;
  final String body;
  final List<String> mentionUserIds;
  final List<int> mentionOffsets;
  final List<int> mentionLengths;
  final Set<String> recipientIds;
  final Map<String, String> notes;
  final BeaconForwardPolicyValue forwardPolicy;

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
      forwardPolicy == other.forwardPolicy;

  @override
  int get hashCode => Object.hash(beaconId, body);

  @override
  String toString() =>
      '_PublishCall($beaconId, "$body", ${mentionUserIds.join(',')}, '
      '$mentionOffsets, $mentionLengths, $recipientIds, $notes, '
      '${forwardPolicy.name})';
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
  /// Everything that reached the server, in order.
  final events = <String>[];
  final publishCalls = <_PublishCall>[];

  /// Errors thrown by successive `postPublish` calls; null/absent = success.
  final publishErrors = <Exception?>[];

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
    Duration? lifetime,
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
      ),
    );
    final index = publishCalls.length - 1;
    if (index < publishErrors.length && publishErrors[index] != null) {
      throw publishErrors[index]!;
    }
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-msg-1');
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
      'creating and publishing a Post never calls Request-only media ops',
      () async {
        // BeaconStageImage / BeaconSetMedia throw BeaconNotRequestException
        // («Operation is only available for Requests») on a Post (#749).
        await cubit.ensureDraft(context: '', showMessage: false);
        await publish();

        expect(write.stagedKeys, isEmpty);
        expect(write.setMediaCalls, isEmpty);
        expect(port.publishCalls, hasLength(1));
      },
    );

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

  group('Post draft failures', () {
    test('a failed attachment save drops the upload so Send and Keep stay usable', () async {
      write.addAttachmentError = Exception('upload failed');
      final upload = _file('a.png');

      await cubit.addPostAttachment(upload);

      expect(cubit.state.postAttachments, isEmpty);
      write.addAttachmentError = null;
      await cubit.addPostAttachment(upload);
      expect(cubit.state.postAttachments.single.attachmentId, isNotNull);
    });

    test('a failed discard keeps the open composer saving its draft', () async {
      await cubit.ensureDraft(context: '', showMessage: false);
      write.deleteError = Exception('delete failed');

      await cubit.discardPost();
      write.deleteError = null;
      await cubit.addPostAttachment(_file('b.png'));

      expect(cubit.state.draftId, 'server-beacon');
      expect(cubit.state.postAttachments.single.attachmentId, isNotNull,
          reason: 'persistence is not disabled by the failed discard');
    });
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
      'sends no attachment: the ones on the draft are already on the server',
      () async {
        final sent = await publish(
          attachments: [_file('a.png'), _file('b.png'), _file('c.png')],
        );

        expect(sent, isTrue);
        expect(port.events, ['publish']);
      },
    );

    test('a published Post is not published again', () async {
      final attachments = [_file('a.png'), _file('b.png')];

      expect(await publish(attachments: attachments), isTrue);
      expect(await publish(attachments: attachments), isTrue);

      expect(port.publishCalls, hasLength(1));
      expect(write.createdFields, hasLength(1));
    });

    test(
      'a second call while one is running is dropped, so a double tap '
      'publishes once',
      () async {
        final attachments = [_file('a.png'), _file('b.png')];

        final first = publish(attachments: attachments);
        final second = publish(attachments: attachments);

        expect(await second, isFalse);
        expect(await first, isTrue);
        expect(port.events, ['publish']);
      },
    );

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
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);

        final retry = await publish(
          body: '@Мария привет',
          mentions: mentions,
          attachments: attachments,
        );

        expect(retry, isTrue);
        expect(port.publishCalls, hasLength(2));
        expect(port.publishCalls[1], port.publishCalls[0]);
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
      expect(port.events, ['publish']);
    });

    test('publishes a single-photo Post with a blank body', () async {
      final sent = await publish(body: '   ', attachments: [_file('a.png')]);

      expect(sent, isTrue);
      expect(port.events, ['publish']);
    });

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
