import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';
import 'fork_beacon_ports.dart';

/// «Now» for every copy below: noon, so a day either side is unambiguous.
final _now = DateTime(2026, 10, 23, 12);

Beacon _source({DateTime? startAt, DateTime? endAt}) => Beacon.empty.copyWith(
  id: 'src',
  title: 'Pick up a parcel',
  description: 'At the post office on Main St, before 6 pm.',
  status: BeaconStatus.open,
  startAt: startAt,
  endAt: endAt,
);

/// Opens «Create from this request» on [source] with the clock at [_now].
Future<BeaconCreateCubit> _openCopy(
  Beacon source, {
  ForkingBeaconWritePort? write,
}) async {
  final cubit = BeaconCreateCubit(
    beaconCreateCase: fakeBeaconCreateCase(
      write: write ?? ForkingBeaconWritePort(source: source),
    ),
    effects: FakeUiEffectPort(),
    forkSourceIdToLoad: source.id,
    forkTitle: (t) => 'Copy of $t',
    clock: () => _now,
  );
  addTearDown(cubit.close);
  if (cubit.state.title.isEmpty) {
    await cubit.stream
        .firstWhere((s) => s.title.isNotEmpty && !s.isLoading)
        .timeout(const Duration(seconds: 2));
  }
  return cubit;
}

void _expectAnytime(BeaconCreateState s) {
  expect(s.startAt, isNull);
  expect(s.endAt, isNull);
  expect(s.cachedDeadlineAt, isNull);
  expect(s.cachedEventStartAt, isNull);
  expect(s.cachedEventEndAt, isNull);
}

void main() {
  group('#607 Create from this request drops a past When?', () {
    test('a deadline that was yesterday opens as Anytime', () async {
      final cubit = await _openCopy(
        _source(endAt: _now.subtract(const Duration(days: 1))),
      );
      _expectAnytime(cubit.state);
      expect(cubit.state.title, 'Copy of Pick up a parcel');
    });

    test('an event that ended yesterday opens as Anytime', () async {
      final cubit = await _openCopy(
        _source(
          startAt: _now.subtract(const Duration(days: 3)),
          endAt: _now.subtract(const Duration(days: 1)),
        ),
      );
      _expectAnytime(cubit.state);
    });

    test('a single-moment event last week opens as Anytime', () async {
      final cubit = await _openCopy(
        _source(startAt: _now.subtract(const Duration(days: 7))),
      );
      _expectAnytime(cubit.state);
    });

    test('a deadline next week is kept', () async {
      final deadline = _now.add(const Duration(days: 7));
      final cubit = await _openCopy(_source(endAt: deadline));
      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, deadline);
      expect(cubit.state.cachedDeadlineAt, deadline);
      expect(cubit.state.cachedEventStartAt, isNull);
      expect(cubit.state.cachedEventEndAt, isNull);
    });

    test('an event next week is kept', () async {
      final start = _now.add(const Duration(days: 7));
      final end = _now.add(const Duration(days: 8));
      final cubit = await _openCopy(_source(startAt: start, endAt: end));
      expect(cubit.state.startAt, start);
      expect(cubit.state.endAt, end);
      expect(cubit.state.cachedDeadlineAt, isNull);
      expect(cubit.state.cachedEventStartAt, start);
      expect(cubit.state.cachedEventEndAt, end);
    });

    test('a deadline today (picked as a date) is kept', () async {
      // The date picker stores a calendar day at local midnight, already
      // behind the clock by noon; today is still a valid deadline.
      final today = DateTime(_now.year, _now.month, _now.day);
      final cubit = await _openCopy(_source(endAt: today));
      expect(cubit.state.endAt, today);
      expect(cubit.state.cachedDeadlineAt, today);
    });

    test('an event that started before and ends next week is kept', () async {
      final start = _now.subtract(const Duration(days: 2));
      final end = _now.add(const Duration(days: 7));
      final cubit = await _openCopy(_source(startAt: start, endAt: end));
      expect(cubit.state.startAt, start);
      expect(cubit.state.endAt, end);
    });

    test('the saved copy of a past When? carries no dates', () async {
      final write = ForkingBeaconWritePort(
        source: _source(
          startAt: _now.subtract(const Duration(days: 3)),
          endAt: _now.subtract(const Duration(days: 1)),
        ),
      );
      final cubit = await _openCopy(write.source, write: write);
      cubit
        ..setAutosaveContext('')
        ..setDescription('Two boxes, not one.');
      await cubit.flushAutosave();

      // The server fork copies the source dates; the follow-up save must
      // write the copy without them.
      expect(write.forkCalls, hasLength(1));
      expect(write.updatedDraftFields, isNotEmpty);
      expect(write.updatedDraftFields.last.id, 'fork-1');
      expect(write.updatedDraftFields.last.startAt, isNull);
      expect(write.updatedDraftFields.last.endAt, isNull);
    });

    test('the saved copy of a future When? keeps its dates', () async {
      final start = _now.add(const Duration(days: 7));
      final end = _now.add(const Duration(days: 8));
      final write = ForkingBeaconWritePort(
        source: _source(startAt: start, endAt: end),
      );
      final cubit = await _openCopy(write.source, write: write);
      cubit
        ..setAutosaveContext('')
        ..setDescription('Two boxes, not one.');
      await cubit.flushAutosave();

      expect(write.updatedDraftFields.last.id, 'fork-1');
      expect(write.updatedDraftFields.last.startAt, start);
      expect(write.updatedDraftFields.last.endAt, end);
    });

    test('a source with no When? stays Anytime', () async {
      final cubit = await _openCopy(_source());
      _expectAnytime(cubit.state);
    });
  });
}
