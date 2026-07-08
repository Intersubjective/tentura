import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/person_forward_case.dart';
import '../message/person_forward_messages.dart';
import 'person_forward_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'person_forward_state.dart';

class PersonForwardCubit extends Cubit<PersonForwardState> {
  PersonForwardCubit({
    required String personId,
    PersonForwardCase? personForwardCase,
    UiEffectPort? effects,
    @visibleForTesting bool debugSkipInitialLoad = false,
  }) : _case =
           personForwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<PersonForwardCase>()),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         personId.startsWith('U')
             ? PersonForwardState(personId: personId)
             : PersonForwardState(
                 personId: personId,
                 status: const StateIsSuccess(),
                 loadError: 'Wrong id: $personId',
               ),
       ) {
    if (state.loadError != null) {
      _effects.emit(ShowError(state.loadError!));
      return;
    }
    if (!debugSkipInitialLoad) {
      unawaited(load());
    }
    _subscribeLiveUpdates();
  }

  final PersonForwardCase? _case;
  final UiEffectPort _effects;

  StreamSubscription<String>? _forwardCompletedSub;
  StreamSubscription<void>? _contactChangesSub;

  void _subscribeLiveUpdates() {
    final case_ = _case;
    if (case_ == null) return;
    _forwardCompletedSub = case_.forwardCompleted.listen((beaconId) {
      if (isClosed || !state.rows.any((r) => r.beacon.id == beaconId)) {
        return;
      }
      unawaited(load());
    });
    _contactChangesSub = case_.contactChanges.listen((_) {
      final person = state.person;
      if (isClosed || person == null) return;
      emit(
        state.copyWith(person: PersonForwardCase.applyContactOverlay(person)),
      );
    });
  }

  @override
  Future<void> close() async {
    await _forwardCompletedSub?.cancel();
    await _contactChangesSub?.cancel();
    return super.close();
  }

  Future<void> load() async {
    final case_ = _case;
    if (case_ == null || isClosed) return;
    emit(state.copyWith(status: StateStatus.isLoading, loadError: null));
    try {
      final load = await case_.load(state.personId);
      if (isClosed) return;
      final selectedId =
          load.rows.any(
            (r) => r.beacon.id == state.selectedBeaconId && r.isEligible,
          )
          ? state.selectedBeaconId
          : null;
      emit(
        state.copyWith(
          person: load.person,
          rows: load.rows,
          selectedBeaconId: selectedId,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess(), loadError: e));
      }
    }
  }

  void selectBeacon(String beaconId) {
    final row = state.rows.where((r) => r.beacon.id == beaconId).firstOrNull;
    if (row == null || !row.isEligible) return;
    emit(state.copyWith(selectedBeaconId: beaconId));
  }

  void setNote(String note) => emit(state.copyWith(note: note));

  Future<void> send() async {
    final case_ = _case;
    final person = state.person;
    final row = state.selectedRow;
    if (case_ == null || person == null || row == null) return;
    if (!person.isSeeingMe || !row.isEligible) return;

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await case_.send(
        beaconId: row.beacon.id,
        personId: person.id,
        note: state.note,
      );
      _effects.emit(ShowMessage(PersonForwardSentMessage(person.shownName)));
      _effects.emit(const NavigateBack());
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      _effects.emit(ShowError(e));
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }
}
