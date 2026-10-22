import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../../domain/port/home_inviter_port.dart';

/// The inviter the first-run panel names (#523); null until known, and stays
/// null when there is none or the lookup fails — the panel then falls back to
/// its generic welcome.
class OrientationInviterCubit extends Cubit<Profile?> {
  OrientationInviterCubit(this._port) : super(null) {
    unawaited(_load());
  }

  final HomeInviterPort _port;

  Future<void> _load() async {
    try {
      final inviter = await _port.fetchMyInviter();
      if (!isClosed && inviter != null && inviter.id.isNotEmpty) {
        emit(inviter);
      }
    } catch (_) {
      // Naming the inviter is a courtesy; the panel works without it.
    }
  }
}
