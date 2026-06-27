export 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/complaint_case.dart';
import 'complaint_messages.dart';
import 'complaint_state.dart';

export 'complaint_state.dart';

class ComplaintCubit extends Cubit<ComplaintState> {
  ComplaintCubit({
    required String id,
    ComplaintType? fixedType,
    ComplaintCase? complaintCase,
    UiEffectPort? effects,
  }) : _complaintCase = complaintCase ?? GetIt.I<ComplaintCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         ComplaintState(
           id: id,
           type: fixedType ?? ComplaintType.violatesCsaePolicy,
           fixedType: fixedType,
         ),
       ) {
    if (fixedType == ComplaintType.accountDeletionRequest) {
      unawaited(_prefillEmail());
    }
  }

  final ComplaintCase _complaintCase;

  final UiEffectPort _effects;

  Future<void> _prefillEmail() async {
    final email = await _complaintCase.resolveDefaultFeedbackEmail();
    if (email == null || isClosed || state.email.isNotEmpty) {
      return;
    }
    emit(state.copyWith(email: email));
  }

  ///
  void setType(ComplaintType? type) {
    if (state.fixedType != null || type == null) {
      return;
    }
    emit(state.copyWith(type: type));
  }

  ///
  void setDetails(String value) => emit(state.copyWith(details: value));

  ///
  void setEmail(String value) => emit(state.copyWith(email: value));

  ///
  Future<void> submit() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _complaintCase.create(
        id: state.id,
        type: state.type,
        email: state.email,
        details: state.details,
      );
      _effects.emit(
        ShowMessage(
          state.fixedType == ComplaintType.accountDeletionRequest
              ? const AccountDeletionRequestSentMessage()
              : const ComplaintSentMessage(),
        ),
      );
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
