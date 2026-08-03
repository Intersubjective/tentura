// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'blocked_users_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'blocked_users_state.dart';

/// Screen-scoped cubit for the blocked-users list (S20).
@injectable
class BlockedUsersCubit extends Cubit<BlockedUsersState> {
  BlockedUsersCubit(
    this._case,
    this._effects,
  ) : super(const BlockedUsersState());

  @visibleForTesting
  BlockedUsersCubit.test({
    required BlockCase case_,
    required UiEffectPort effects,
  }) : _case = case_,
       _effects = effects,
       super(const BlockedUsersState());

  final BlockCase _case;

  final UiEffectPort _effects;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      emit(
        state.copyWith(
          blocks: List<BlockIntent>.from(await _case.fetchMyBlocks()),
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  /// Top-level "Unblock" on a direct-block row (`objectId` is the blocked user).
  Future<void> unblock(String objectId) async {
    try {
      await _case.unblock(objectId: objectId);
      await _reloadBlocks(collapseWhenOriginMissing: true);
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  /// "Unhide" on an inherited row — releases the whole cascade under [originId],
  /// not a single inherited person (no server single-row release in this pass).
  Future<void> unhideOrigin(String originId) async {
    try {
      await _case.unblock(objectId: originId);
      await _reloadBlocks(collapseWhenOriginMissing: true);
      collapseInherited();
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> promoteToDirect(String objectId) async {
    try {
      await _case.promote(objectId: objectId);
      final expandedOriginId = state.expandedOriginId;
      await _reloadBlocks(collapseWhenOriginMissing: true);
      if (expandedOriginId != null &&
          state.blocks.any((b) => b.id == expandedOriginId)) {
        await _reloadInherited(expandedOriginId);
      }
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> expandInherited(String originId) async {
    emit(
      state.copyWith(
        expandedOriginId: originId,
        expandedInherited: const [],
        expandedLoading: true,
      ),
    );
    await _reloadInherited(originId);
  }

  void collapseInherited() {
    emit(
      state.copyWith(
        expandedOriginId: null,
        expandedInherited: const [],
        expandedLoading: false,
      ),
    );
  }

  Future<void> _reloadInherited(String originId) async {
    try {
      emit(
        state.copyWith(
          expandedInherited: List.from(
            await _case.fetchInherited(originId: originId),
          ),
          expandedLoading: false,
        ),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(
        state.copyWith(
          expandedOriginId: null,
          expandedInherited: const [],
          expandedLoading: false,
        ),
      );
    }
  }

  /// Post-mutation refresh without toggling the list-level loading indicator.
  Future<void> _reloadBlocks({required bool collapseWhenOriginMissing}) async {
    try {
      final blocks = List<BlockIntent>.from(await _case.fetchMyBlocks());
      final expandedOriginId = state.expandedOriginId;
      final originStillPresent =
          expandedOriginId != null &&
          blocks.any((intent) => intent.id == expandedOriginId);
      emit(
        state.copyWith(
          blocks: blocks,
          expandedOriginId: collapseWhenOriginMissing && !originStillPresent
              ? null
              : expandedOriginId,
          expandedInherited: collapseWhenOriginMissing && !originStillPresent
              ? const []
              : state.expandedInherited,
          expandedLoading: collapseWhenOriginMissing && !originStillPresent
              ? false
              : state.expandedLoading,
        ),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
    }
  }
}
