import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/platform_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import 'app_update_state.dart';

export 'app_update_state.dart';

/// Returns negative if [a] < [b], zero if equal, positive if [a] > [b].
int compareSemver(String a, String b) {
  List<int> parseParts(String s) {
    var t = s.trim();
    if (t.startsWith('v') || t.startsWith('V')) {
      t = t.substring(1);
    }
    final dash = t.indexOf('-');
    if (dash >= 0) {
      t = t.substring(0, dash);
    }
    final parts = t.split('.');
    return List<int>.generate(3, (i) {
      if (i >= parts.length) {
        return 0;
      }
      return int.tryParse(parts[i]) ?? 0;
    });
  }

  final pa = parseParts(a);
  final pb = parseParts(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) {
      return c;
    }
  }
  return 0;
}

@singleton
class AppUpdateCubit extends Cubit<AppUpdateState> {
  AppUpdateCubit({
    required RemoteApiService remoteApiService,
    required PlatformRepository platformRepository,
  }) : _platformRepository = platformRepository,
       super(const AppUpdateState()) {
    _minVersionSubscription = remoteApiService.minClientVersionStream.listen(
      _onMinClientVersion,
      cancelOnError: false,
    );
  }

  final PlatformRepository _platformRepository;

  late final StreamSubscription<String> _minVersionSubscription;

  Future<void> _onMinClientVersion(String min) async {
    if (state.dismissed || state.updateAvailable) {
      return;
    }
    try {
      final current = await _platformRepository.getAppVersion();
      if (compareSemver(current, min) < 0) {
        emit(
          state.copyWith(
            updateAvailable: true,
            minVersion: min,
          ),
        );
      }
    } on Object {
      // ignore: version check is best-effort
    }
  }

  void dismiss() {
    if (state.dismissed) {
      return;
    }
    emit(state.copyWith(dismissed: true));
  }

  @disposeMethod
  Future<void> dispose() async {
    await _minVersionSubscription.cancel();
    return close();
  }
}
