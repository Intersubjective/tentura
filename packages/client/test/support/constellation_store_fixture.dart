import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import 'test_realtime_sync.dart';

/// Real store and controllable account/realtime boundaries for read-side tests.
/// Timers use the test zone, so fakeAsync can drive refresh scheduling.
final class ConstellationStoreFixture {
  ConstellationStoreFixture(
    ConstellationRepositoryPort repository, {
    required String accountId,
    DateTime Function()? now,
    ClockPort? clock,
    WakeUpPort? wakeUp,
    RealtimeSyncCase? realtime,
  }) : account = BehaviorSubject<String>.seeded(accountId) {
    final ownedRealtime = realtime == null ? buildTestRealtimeSync() : null;
    store = ConstellationFieldStoreCase(
      repository,
      _AccountPort(account.stream),
      clock ?? _ClockPort(now ?? DateTime.now),
      wakeUp ?? _WakeUpPort(),
      realtime ?? ownedRealtime!.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationStoreFixture'),
    );
    addTearDown(() async {
      // fakeAsync callers explicitly drain cleanup before leaving their zone.
      if (account.isClosed) return;
      await store.dispose();
      await account.close();
      await ownedRealtime?.port.dispose();
    });
  }

  final BehaviorSubject<String> account;
  late final ConstellationFieldStoreCase store;

  Future<void> ready() => Future<void>.delayed(Duration.zero);

  ConstellationCubit createCubit({
    required Profile viewer,
    ForwardRepository? forwardRepository,
    ConstellationPresentationComposer? composePresentation,
  }) {
    final cubit = composePresentation == null
        ? ConstellationCubit(
            case_: store,
            viewer: viewer,
            loadOnCreate: false,
            forwardRepository: forwardRepository,
          )
        : ConstellationCubit(
            case_: store,
            viewer: viewer,
            loadOnCreate: false,
            forwardRepository: forwardRepository,
            composePresentation: composePresentation,
          );
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    return cubit;
  }
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _ClockPort implements ClockPort {
  _ClockPort(this._now);

  final DateTime Function() _now;

  @override
  DateTime now() => _now().toUtc();
}

final class _WakeUpPort implements WakeUpPort {
  @override
  WakeUpHandle schedule(Duration delay, void Function() callback) =>
      _WakeUpHandle(Timer(delay, callback));
}

final class _WakeUpHandle implements WakeUpHandle {
  _WakeUpHandle(this.timer);

  final Timer timer;

  @override
  bool get isActive => timer.isActive;

  @override
  void cancel() => timer.cancel();
}
