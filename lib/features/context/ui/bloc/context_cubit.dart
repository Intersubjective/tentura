import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/context_repository.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'context_state.dart';

class ContextCubit extends Cubit<ContextState> {
  ContextCubit(this._repository) : super(const ContextState()) {
    _fetchSubscription.resume();
  }

  final ContextRepository _repository;

  late final _fetchSubscription = _repository.stream.listen(
    (e) => emit(ContextState(contexts: e.toSet())),
    onError: (Object e) => emit(state.setError(e.toString())),
    cancelOnError: false,
  );

  @override
  Future<void> close() async {
    await _fetchSubscription.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    emit(state.setLoading());
    return _repository.fetch();
  }

  void select(String? context) => emit(state.copyWith(selected: context));

  Future<void> add(String contextName) async {
    try {
      final context = await _repository.add(contextName);
      emit(state.copyWith(
        selected: context,
        contexts: {
          context,
          ...state.contexts,
        },
      ));
    } catch (e) {
      emit(state.setError(e));
    }
  }

  Future<void> delete(String contextName) async {
    try {
      final context = await _repository.delete(contextName);
      state.contexts.remove(context);
      emit(state.copyWith(
          contexts: Set.from(state.contexts),
          selected: state.selected == context ? '' : null));
    } catch (e) {
      emit(state.setError(e));
    }
  }
}
