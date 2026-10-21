import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';

import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

void main() {
  test('quiet autosave skips short titles and edit/live', () async {
    final write = FakeBeaconWritePort();
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.setAutosaveContext('');

    cubit.setTitle('ab');
    await cubit.flushAutosave();
    expect(write.createdFields, isEmpty);
    expect(cubit.state.isAutosaving, isFalse);
    expect(cubit.state.status, isA<StateIsSuccess>());

    cubit.setTitle('Valid title');
    cubit.setDescription('A description that is required.');
    await cubit.flushAutosave();
    expect(write.createdFields, isNotEmpty);
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.draftId, isNotNull);
    expect(cubit.state.lastAutosavedAt, isNotNull);
  });

  test(
    'title shorter than min length never persists Draft placeholder',
    () async {
      final write = FakeBeaconWritePort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.setAutosaveContext('');

      cubit.setTitle('x' * (kTitleMinLength - 1));
      await cubit.flushAutosave();
      expect(write.createdFields, isEmpty);
    },
  );

  test('flushAutosave waits for an in-flight quiet persist', () async {
    final hold = Completer<void>();
    final write = FakeBeaconWritePort()..createHold = hold;
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit
      ..setAutosaveContext('')
      ..setTitle('Valid title')
      ..setDescription('A description that is required.');

    final first = cubit.flushAutosave();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isAutosaving, isTrue);

    final second = cubit.flushAutosave();
    hold.complete();
    await Future.wait([first, second]);
    expect(cubit.state.isAutosaving, isFalse);
    expect(write.createdFields, hasLength(1));
  });

  test(
    'title without a description does not autosave or raise an error',
    () async {
      // The server refuses a standalone draft with no description; saving
      // after the title alone left a sticky "Description is required"
      // snackbar over the form while the user was still typing.
      final write = FakeBeaconWritePort();
      final effects = FakeUiEffectPort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: effects,
      );
      addTearDown(cubit.close);
      cubit.setAutosaveContext('');

      cubit.setTitle('Borrow a ladder');
      await cubit.flushAutosave();
      expect(write.createdFields, isEmpty);
      expect(effects.emitted, isEmpty);

      cubit.setDescription('Need a 3 m ladder this weekend.');
      await cubit.flushAutosave();
      expect(write.createdFields, isNotEmpty);
    },
  );

  // #494: after a failed autosave the footer kept "Draft saved · just now"
  // from the previous save, beside the error bar saying the save failed.
  test('a failed autosave drops the earlier "saved" time', () async {
    final write = FakeBeaconWritePort();
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.setAutosaveContext('');
    cubit
      ..setTitle('Valid title')
      ..setDescription('A description that is required.');
    await cubit.flushAutosave();
    expect(cubit.state.lastAutosavedAt, isNotNull);

    write.updateDraftError = Exception('cover upload failed');
    cubit.setDescription('A description that changed.');
    await cubit.flushAutosave();

    expect(write.updatedDraftFields, isEmpty);
    expect(cubit.state.isAutosaving, isFalse);
    expect(cubit.state.lastAutosavedAt, isNull);
  });
  // #625: deleting the draft from the editor must stop autosave for good, or
  // the pending edit is written to the deleted id.
  group('deleteDraft (#625)', () {
    Future<(BeaconCreateCubit, FakeUiEffectPort)> savedDraft(
      FakeBeaconWritePort write,
    ) async {
      final effects = FakeUiEffectPort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: effects,
      );
      addTearDown(cubit.close);
      cubit
        ..setAutosaveContext('')
        ..setTitle('Valid title')
        ..setDescription('A description that is required.');
      await cubit.flushAutosave();
      expect(cubit.state.draftId, isNotNull);
      return (cubit, effects);
    }

    int writes(FakeBeaconWritePort w) =>
        w.createdFields.length +
        w.updatedDraftFields.length +
        w.updatedFields.length;

    test('cancels the pending autosave and forgets the deleted id', () async {
      final write = FakeBeaconWritePort();
      final (cubit, effects) = await savedDraft(write);
      final id = cubit.state.draftId;
      cubit.setDescription('An edit still waiting on the debounce.');
      final before = writes(write);

      final deleted = await cubit.deleteDraft(navigateBack: false);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await cubit.flushAutosave();

      expect(deleted, isTrue);
      expect(write.deletedIds, [id]);
      expect(writes(write), before);
      expect(cubit.state.draftId, isNull);
      expect(cubit.state.isLoading, isFalse);
      expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    });

    test('waits for an autosave already on the wire before deleting', () async {
      final write = _HeldUpdateDraftPort();
      final (cubit, _) = await savedDraft(write);
      final id = cubit.state.draftId;
      write.hold = Completer<void>();
      cubit.setDescription('An edit being saved right now.');
      final saving = cubit.flushAutosave();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isAutosaving, isTrue);

      final deleting = cubit.deleteDraft(navigateBack: false);
      await Future<void>.delayed(Duration.zero);
      expect(write.deletedIds, isEmpty);
      write.hold!.complete();
      await Future.wait([saving, deleting]);

      expect(write.deletedIds, [id]);
      final before = writes(write);
      cubit.setTitle('Another valid title');
      await cubit.flushAutosave();
      expect(writes(write), before);
    });

    test('keeps autosaving when the delete fails', () async {
      final write = _FailingDeletePort();
      final (cubit, _) = await savedDraft(write);
      final id = cubit.state.draftId;

      final deleted = await cubit.deleteDraft(navigateBack: false);
      expect(deleted, isFalse);
      expect(cubit.state.draftId, id);

      cubit.setDescription('An edit after the failed delete.');
      await cubit.flushAutosave();
      expect(write.updatedDraftFields.last.id, id);
    });

    // Guard: other callers (the constellation composer's cancel) still get
    // the delete and the NavigateBack they had.
    test('by default still deletes and navigates back', () async {
      final write = FakeBeaconWritePort();
      final (cubit, effects) = await savedDraft(write);
      final id = cubit.state.draftId;

      await cubit.deleteDraft();

      expect(write.deletedIds, [id]);
      expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
    });
  });

  // #607: leaving the editor while an autosave was on the wire waited on
  // `stream.firstWhere`, which throws a StateError when the cubit closes
  // (the screen is disposed) before that autosave lands.
  group('cubit closes while an autosave is in flight (#607)', () {
    Future<(BeaconCreateCubit, FakeBeaconWritePort, Completer<void>)>
    inFlight() async {
      final hold = Completer<void>();
      final write = FakeBeaconWritePort()..createHold = hold;
      final cubit =
          BeaconCreateCubit(
              beaconCreateCase: fakeBeaconCreateCase(write: write),
              effects: FakeUiEffectPort(),
            )
            ..setAutosaveContext('')
            ..setTitle('Valid title')
            ..setDescription('A description that is required.');
      unawaited(cubit.flushAutosave());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isAutosaving, isTrue);
      return (cubit, write, hold);
    }

    test('flushAutosave completes without a StateError', () async {
      final (cubit, _, hold) = await inFlight();

      final flush = cubit.flushAutosave();
      await cubit.close();
      hold.complete();

      await expectLater(flush, completes);
    });

    test('discardDraft completes and still deletes the new draft', () async {
      final (cubit, write, hold) = await inFlight();

      final discard = cubit.discardDraft();
      await cubit.close();
      hold.complete();

      await expectLater(discard, completes);
      expect(write.deletedIds, ['server-beacon']);
    });
  });

  // #607: «Keep draft» is offered only when leaving really keeps one.
  group('keepsDraftOnLeave (#607)', () {
    BeaconCreateCubit build(FakeBeaconWritePort write) {
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      return cubit..setAutosaveContext('');
    }

    test('false for a title too short to autosave', () async {
      final cubit = build(FakeBeaconWritePort())
        ..setTitle('x' * (kTitleMinLength - 1))
        ..setDescription('A description that is required.');
      expect(cubit.keepsDraftOnLeave, isFalse);
    });

    test('false for a standalone title with no description', () async {
      final cubit = build(FakeBeaconWritePort())..setTitle('Borrow a ladder');
      expect(cubit.keepsDraftOnLeave, isFalse);
    });

    test('true once the form would autosave', () async {
      final cubit = build(FakeBeaconWritePort())
        ..setTitle('Borrow a ladder')
        ..setDescription('Need a 3 m ladder this weekend.');
      expect(cubit.keepsDraftOnLeave, isTrue);
    });

    test('true for a saved draft even after the title is cut short', () async {
      final write = FakeBeaconWritePort();
      final cubit = build(write)
        ..setTitle('Borrow a ladder')
        ..setDescription('Need a 3 m ladder this weekend.');
      await cubit.flushAutosave();
      expect(cubit.state.draftId, isNotNull);

      cubit.setTitle('ab');
      expect(cubit.keepsDraftOnLeave, isTrue);
    });
  });
}

class _HeldUpdateDraftPort extends FakeBeaconWritePort {
  Completer<void>? hold;

  @override
  Future<Beacon> updateDraft(Beacon fields) async {
    final h = hold;
    if (h != null) await h.future;
    return super.updateDraft(fields);
  }
}

class _FailingDeletePort extends FakeBeaconWritePort {
  @override
  Future<void> delete(String id) async => throw Exception('network down');
}
