import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';
import 'fork_beacon_ports.dart';

final _source = Beacon.empty.copyWith(
  id: 'src',
  title: 'Pick up a parcel',
  description: 'At the post office on Main St, before 6 pm.',
  status: BeaconStatus.open,
  images: const [ImageEntity(id: 'src-img', authorId: 'author-1')],
  coverImageId: 'src-img',
);

String _copyOf(String title) => 'Copy of $title';

/// Builds the editor opened by «Create from this request» and waits for the
/// source to load.
Future<BeaconCreateCubit> _openCopy(
  ForkingBeaconWritePort write, {
  List<PlanStepTime>? planStepTimes,
}) async {
  final cubit = BeaconCreateCubit(
    beaconCreateCase: fakeBeaconCreateCase(write: write),
    effects: FakeUiEffectPort(),
    forkSourceIdToLoad: write.source.id,
    forkPlanStepTimes: planStepTimes,
    forkTitle: _copyOf,
  );
  addTearDown(cubit.close);
  if (cubit.state.title.isEmpty) {
    await cubit.stream
        .firstWhere((s) => s.title.isNotEmpty && !s.isLoading)
        .timeout(const Duration(seconds: 2));
  }
  // The screen arms autosave on its first build.
  cubit.setAutosaveContext('');
  return cubit;
}

void main() {
  group('#493 Create from this request defers the draft', () {
    test(
      'opening the copy makes no server draft and prefills Copy of',
      () async {
        final write = ForkingBeaconWritePort(source: _source);
        final cubit = await _openCopy(write);

        expect(cubit.state.title, 'Copy of Pick up a parcel');
        expect(cubit.state.description, _source.description);
        // The source's images arrive with the fork (re-uploaded), not before.
        expect(
          [for (final i in cubit.state.images) i.id],
          isNot(contains('src-img')),
        );

        // Leaving the editor flushes autosave; an untouched copy still saves
        // nothing.
        await cubit.flushAutosave();

        expect(write.forkCalls, isEmpty);
        expect(write.createdFields, isEmpty);
        expect(write.updatedDraftFields, isEmpty);
        expect(write.setMediaCalls, isEmpty);
        expect(cubit.state.draftId, isNull);
      },
    );

    test('the first edit forks once and saves the edited copy', () async {
      final write = ForkingBeaconWritePort(source: _source);
      final cubit = await _openCopy(write);

      cubit.setDescription('Two boxes, not one.');
      await cubit.flushAutosave();

      // The draft comes from the lineage fork, never from a plain create.
      expect(write.createdFields, isEmpty);
      expect(write.forkCalls, hasLength(1));
      expect(write.forkCalls.single.sourceId, 'src');
      expect(write.forkCalls.single.copyPlan, isFalse);
      expect(cubit.state.draftId, 'fork-1');

      expect(write.updatedDraftFields, isNotEmpty);
      final saved = write.updatedDraftFields.last;
      expect(saved.id, 'fork-1');
      expect(saved.title, 'Copy of Pick up a parcel');
      expect(saved.description, 'Two boxes, not one.');

      // The fork copied the images under new ids: the follow-up save keeps
      // those and never points the draft at the source's images.
      final mediaIds = [for (final c in write.setMediaCalls) ...c.imageIds];
      expect(mediaIds, isNot(contains('src-img')));
      if (write.setMediaCalls.isNotEmpty) {
        expect(write.setMediaCalls.last.beaconId, 'fork-1');
        expect(write.setMediaCalls.last.imageIds, ['copy-img']);
      }
      expect([for (final i in cubit.state.images) i.id], ['copy-img']);

      // Later edits update the same draft.
      cubit.setDescription('Two boxes and a letter.');
      await cubit.flushAutosave();
      expect(write.forkCalls, hasLength(1));
      expect(write.createdFields, isEmpty);
      expect(write.updatedDraftFields.last.id, 'fork-1');
    });

    test('an explicit Save draft without edits forks exactly once', () async {
      final write = ForkingBeaconWritePort(source: _source);
      final cubit = await _openCopy(write);

      await cubit.saveDraft(context: '', showMessage: false);
      expect(write.forkCalls, hasLength(1));
      expect(cubit.state.draftId, 'fork-1');

      await cubit.saveDraft(context: '', showMessage: false);
      expect(write.forkCalls, hasLength(1));
      expect(write.createdFields, isEmpty);
      expect(write.updatedDraftFields.last.id, 'fork-1');
      expect(write.updatedDraftFields.last.title, 'Copy of Pick up a parcel');
    });

    test('overlapping first saves share one fork', () async {
      final write = ForkingBeaconWritePort(source: _source)
        ..forkHold = Completer<void>();
      final cubit = await _openCopy(write);

      final first = cubit.ensureDraft(context: '', showMessage: false);
      final second = cubit.ensureDraft(context: '', showMessage: false);
      await Future<void>.delayed(Duration.zero);
      write.forkHold!.complete();

      expect(await Future.wait([first, second]), ['fork-1', 'fork-1']);
      expect(write.forkCalls, hasLength(1));
      expect(write.createdFields, isEmpty);

      // The server fork copies the source title verbatim; the draft the
      // recipients step / Next lands on must already carry the Copy-of title.
      expect(write.updatedDraftFields, isNotEmpty);
      expect(write.updatedDraftFields.last.id, 'fork-1');
      expect(write.updatedDraftFields.last.title, 'Copy of Pick up a parcel');
      expect(write.beacon.title, 'Copy of Pick up a parcel');
    });

    test('the plan choice made before opening reaches the fork', () async {
      final times = [
        PlanStepTime(
          sourceStepId: 'step-1',
          startAt: DateTime.utc(2026, 11, 2, 9),
          endAt: DateTime.utc(2026, 11, 2, 10),
        ),
      ];
      final write = ForkingBeaconWritePort(source: _source);
      final cubit = await _openCopy(write, planStepTimes: times);

      expect(write.forkCalls, isEmpty);
      cubit.setDescription('Same plan, new week.');
      await cubit.flushAutosave();

      expect(write.forkCalls, hasLength(1));
      expect(write.forkCalls.single.copyPlan, isTrue);
      expect(write.forkCalls.single.planStepTimes, times);
    });

    test('a long source title still fits after Copy of', () async {
      final write = ForkingBeaconWritePort(
        source: _source.copyWith(title: 'x' * kBeaconTitleMaxLength),
      );
      final cubit = await _openCopy(write);

      expect(cubit.state.title, startsWith('Copy of '));
      expect(
        cubit.state.title.length,
        lessThanOrEqualTo(kBeaconTitleMaxLength),
      );
    });
  });
}
