export 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../data/repository/complaint_repository.dart';
import 'complaint_messages.dart';
import 'complaint_state.dart';

export 'complaint_state.dart';

class ComplaintCubit extends Cubit<ComplaintState> {
  ComplaintCubit({
    required String id,
    ComplaintRepository? complaintRepository,
    UiEffectPort? effects,
  }) : _complaintRepository =
           complaintRepository ?? GetIt.I<ComplaintRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(ComplaintState(id: id));

  final ComplaintRepository _complaintRepository;

  final UiEffectPort _effects;

  ///
  void setType(ComplaintType? type) {
    if (type != null) {
      emit(state.copyWith(type: type));
    }
  }

  ///
  void setDetails(String value) => emit(state.copyWith(details: value));

  ///
  void setEmail(String value) => emit(state.copyWith(email: value));

  ///
  Future<void> submit() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _complaintRepository.create(
        id: state.id,
        type: state.type,
        email: state.email,
        details: state.details,
      );
      _effects.emit(const ShowMessage(ComplaintSentMessage()));
      _effects.emit(const NavigateBack());
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      _effects.emit(ShowError(e));
      _effects.emit(const NavigateBack());
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }
}
