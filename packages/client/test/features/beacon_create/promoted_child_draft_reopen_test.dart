import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/beacon_create_case_factory.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _context = BeaconCreationContextPromotedChild(
  parentBeaconId: 'parent-1',
  sourceMessageId: 'msg-1',
);
const _oldId = 'cmd-old';
const _originalTitle = 'Original title';
const _otherTitle = 'Other title';

class _DraftServer extends FakeBeaconHierarchyRepositoryPort {
  _DraftServer({this.replacementError, this.rejectEveryCommand = false});

  final Object? replacementError;
  final bool rejectEveryCommand;

  @override
  Future<BeaconChildCreateOutcome> createChild({
    required String parentBeaconId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool draft = false,
  }) {
    createError =
        rejectEveryCommand ||
            (clientCommandId == _oldId && title != _originalTitle)
        ? const BeaconChildCommandConflictException()
        : clientCommandId == _oldId
        ? null
        : replacementError;
    createOutcomeOverride = clientCommandId == _oldId
        ? const BeaconChildCreateOutcome(
            outcome: BeaconChildCommandOutcome.replayed,
            beaconId: 'draft-9',
          )
        : const BeaconChildCreateOutcome(
            outcome: BeaconChildCommandOutcome.created,
            beaconId: 'replacement-draft',
          );
    return super.createChild(
      parentBeaconId: parentBeaconId,
      sourceMessageId: sourceMessageId,
      clientCommandId: clientCommandId,
      title: title,
      description: description,
      context: context,
      coordinates: coordinates,
      startAt: startAt,
      endAt: endAt,
      tags: tags,
      needs: needs,
      primaryNeedSlug: primaryNeedSlug,
      addressLabel: addressLabel,
      draft: draft,
    );
  }
}

Future<InMemoryBeaconChildCommandStore> _savedCommands() async {
  final store = InMemoryBeaconChildCommandStore();
  await store.write(_context, _oldId);
  return store;
}

Future<BeaconCreateCubit> _reopen(
  InMemoryBeaconChildCommandStore store,
  _DraftServer server,
  FakeUiEffectPort effects,
  String title,
) async {
  final write = FakeBeaconWritePort();
  final createCase = buildBeaconCreateCase(beacons: write);
  final cubit = BeaconCreateCubit(
    beaconCreateCase: createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      server,
      createCase: createCase,
      beacons: write,
      commandStore: store,
    ),
    childCreationContext: _context,
    postBuddingEnabled: false,
    effects: effects,
  );
  addTearDown(cubit.close);
  if (cubit.state.clientCommandId == null) {
    await cubit.stream
        .firstWhere((state) => state.clientCommandId != null)
        .timeout(const Duration(seconds: 5));
  }
  cubit
    ..setTitle(title)
    ..setDescription('Help on Saturday.');
  return cubit;
}

Matcher _createCall(String title, Matcher commandId) => allOf(
  containsPair('parentBeaconId', _context.parentBeaconId),
  containsPair('sourceMessageId', _context.sourceMessageId),
  containsPair('title', title),
  containsPair('draft', true),
  containsPair('clientCommandId', commandId),
);

void main() {
  test(
    'reopening replays the same input and saves changed input without an error',
    () async {
      final replayServer = _DraftServer();
      final replay = await _reopen(
        await _savedCommands(),
        replayServer,
        FakeUiEffectPort(),
        _originalTitle,
      );

      expect(await replay.ensureDraft(context: ''), 'draft-9');
      expect(replay.state.draftId, 'draft-9');
      expect(replayServer.createCalls, [
        _createCall(_originalTitle, equals(_oldId)),
      ]);

      final server = _DraftServer();
      final effects = FakeUiEffectPort();
      final changed = await _reopen(
        await _savedCommands(),
        server,
        effects,
        _otherTitle,
      );

      final id = await changed.ensureDraft(context: '');

      expect(changed.state.status, isA<StateIsSuccess>());
      expect(id, 'replacement-draft');
      expect(changed.state.draftId, id);
      expect(server.createCalls.last, _createCall(_otherTitle, isNot(_oldId)));
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    },
  );

  test(
    'a network failure keeps the replacement command for the next composer',
    () async {
      final store = await _savedCommands();
      final server = _DraftServer(
        replacementError: ClientException('Connection closed before the reply'),
      );
      final cubit = await _reopen(
        store,
        server,
        FakeUiEffectPort(),
        _otherTitle,
      );

      expect(await cubit.ensureDraft(context: ''), isNull);
      expect(cubit.state.draftId, isNull);
      final replacementId = await store.read(_context);
      expect(replacementId, allOf(isNotEmpty, isNot(_oldId)));
      expect(
        server.createCalls.last,
        _createCall(_otherTitle, equals(replacementId)),
      );

      final nextServer = _DraftServer();
      final next = await _reopen(
        store,
        nextServer,
        FakeUiEffectPort(),
        _otherTitle,
      );
      expect(await next.ensureDraft(context: ''), 'replacement-draft');
      expect(
        nextServer.createCalls.single,
        _createCall(_otherTitle, equals(replacementId)),
      );
    },
  );

  test(
    'a persistent conflict shows one localized error and leaves saving idle',
    () async {
      final server = _DraftServer(rejectEveryCommand: true);
      final effects = FakeUiEffectPort();
      final cubit = await _reopen(
        await _savedCommands(),
        server,
        effects,
        _otherTitle,
      );

      expect(await cubit.ensureDraft(context: ''), isNull);
      expect(server.createCalls, isNotEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(effects.emitted.whereType<ShowError>(), [
        isA<ShowError>().having(
          (effect) => effect.error,
          'error',
          isA<BeaconChildCommandConflictException>().having(
            (error) => error.toL10n('en'),
            'English message',
            "Couldn't submit this request. Please try again.",
          ),
        ),
      ]);
    },
  );
}
