import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:meta/meta.dart';

import 'package:tentura/domain/util/availability_presets.dart';
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
    DateTime Function()? clock,
    @visibleForTesting bool debugSkipInitialLoad = false,
  }) : _case =
           personForwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<PersonForwardCase>()),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       _clock = clock ?? DateTime.now,
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
  final DateTime Function() _clock;

  DateTime _todayUtc() => availabilityTodayUtc(_clock);

  /// UTC calendar date for availability UI; uses the cubit clock in tests.
  DateTime get todayUtc => _todayUtc();

  StreamSubscription<String>? _forwardChangesSub;
  StreamSubscription<void>? _contactChangesSub;

  void _subscribeLiveUpdates() {
    final case_ = _case;
    if (case_ == null) return;
    _forwardChangesSub = case_.forwardChanges.listen((beaconId) {
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
    await _forwardChangesSub?.cancel();
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
    if (!person.isMutuallyVisible || !row.isEligible) return;

    if (person.availability.blocksNewRequestsOn(_todayUtc())) {
      _effects.emit(
        ShowMessage(
          PersonForwardAvailabilitySkippedMessage(person.shownName),
        ),
      );
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await case_.send(
        beaconId: row.beacon.id,
        personId: person.id,
        note: state.note,
      );
      if (result.deliveredRecipientIds.contains(person.id)) {
        _effects.emit(ShowMessage(PersonForwardSentMessage(person.shownName)));
        _effects.emit(const NavigateBack());
      } else if (result.availabilitySkippedRecipientIds.contains(person.id)) {
        _effects.emit(
          ShowMessage(
            PersonForwardAvailabilitySkippedMessage(person.shownName),
          ),
        );
      } else {
        _effects.emit(
          ShowError(
            StateError(
              'Forward did not deliver to ${person.id}',
            ),
          ),
        );
      }
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
