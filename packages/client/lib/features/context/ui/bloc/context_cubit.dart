import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../data/repository/context_repository.dart';
import '../../domain/exception.dart';
import '../../domain/entity/context_entity.dart';
import 'context_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'context_state.dart';

class ContextCubit extends Cubit<ContextState> {
  ContextCubit({
    AuthCase? authCase,
    ContextRepository? contextRepository,
    bool fetchFromCache = true,
  }) : _authCase = authCase ?? GetIt.I<AuthCase>(),
       _contextRepository = contextRepository ?? GetIt.I<ContextRepository>(),
       super(const ContextState()) {
    _authChanges = _authCase.currentAccountChanges().listen(
      _onAuthChanges,
      cancelOnError: false,
    );
    _contextChanges = _contextRepository.changes.listen(
      _onContextChanges,
      cancelOnError: false,
      onError: _onContextChangesError,
    );
    unawaited(fetch(fromCache: fetchFromCache));
  }

  final AuthCase _authCase;

  final ContextRepository _contextRepository;

  StreamSubscription<String>? _authChanges;

  StreamSubscription<RepositoryEvent<ContextEntity>>? _contextChanges;

  @override
  Future<void> close() async {
    await _authChanges?.cancel();
    await _contextChanges?.cancel();
    await super.close();
  }

  ///
  ///
  Future<void> fetch({bool fromCache = true}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final contexts = await _contextRepository.fetch(fromCache: fromCache);
      emit(
        ContextState(
          contexts: contexts.toSet(),
          selected: state.selected,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  void select(String contextName) => emit(
    ContextState(
      contexts: state.contexts,
      selected: contextName,
    ),
  );

  ///
  ///
  Future<void> add(String? contextName) async {
    if (contextName == null) {
      return;
    } else if (state.contexts.contains(contextName)) {
      select(contextName);
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _contextRepository.add(contextName);
      emit(
        state.copyWith(
          selected: contextName,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  Future<void> delete(String contextName) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _contextRepository.delete(
        userId: await _authCase.getCurrentAccountId(),
        contextName: contextName,
      );
      if (contextName == state.selected) {
        emit(state.copyWith(selected: ''));
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  Future<void> _onAuthChanges(String id) async {
    if (id.isNotEmpty) {
      await fetch(fromCache: false);
    }
  }

  ///
  ///
  void _onContextChanges(RepositoryEvent<ContextEntity> event) =>
      switch (event) {
        final RepositoryEventCreate<ContextEntity> entity => emit(
          ContextState(
            contexts: state.contexts..add(entity.value.name),
            selected: state.selected,
          ),
        ),
        final RepositoryEventDelete<ContextEntity> entity => emit(
          ContextState(
            contexts: state.contexts..remove(entity.id),
            selected: state.selected == entity.id ? '' : state.selected,
          ),
        ),
        RepositoryEventUpdate<ContextEntity>() => null,
        RepositoryEventFetch<ContextEntity>() => null,
      };

  ///
  ///
  void _onContextChangesError(Object? e) => emit(
    state.copyWith(
      status: StateHasError(e ?? const ContextUnknownException()),
    ),
  );
}
