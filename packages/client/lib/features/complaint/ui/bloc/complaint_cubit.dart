import 'package:get_it/get_it.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/repository/complaint_repository.dart';
import 'complaint_messages.dart';
import 'complaint_state.dart';

export 'complaint_state.dart';

class ComplaintCubit extends Cubit<ComplaintState> {
  ComplaintCubit({
    required String id,
    ComplaintRepository? complaintRepository,
  }) : _complaintRepository =
           complaintRepository ?? GetIt.I<ComplaintRepository>(),
       super(ComplaintState(id: id));

  final ComplaintRepository _complaintRepository;

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
      emit(
        state.copyWith(
          status: StateIsMessaging(const ComplaintSentMessage()),
        ),
      );
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
      emit(state.copyWith(status: StateIsNavigating.back));
    }
  }
}
