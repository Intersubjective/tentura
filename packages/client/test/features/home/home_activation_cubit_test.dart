import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';

final class _FakePreferences implements HomeOrientationPreferencesPort {
  final activated = <String, bool>{};
  final dismissed = <String, bool>{};
  var debugOverride = OrientationDebugOverride.auto;
  int setActivatedCalls = 0;

  String activatedReadDelayUserId = '';
  Completer<bool>? activatedReadDelay;

  @override
  Future<bool> isActivated({required String userId}) async {
    if (activatedReadDelay != null &&
        userId == activatedReadDelayUserId) {
      return activatedReadDelay!.future;
    }
    return activated[userId] ?? false;
  }

  @override
  Future<void> setActivated({required String userId}) async {
    setActivatedCalls++;
    activated[userId] = true;
  }

  @override
  Future<bool> isOrientationDismissed({required String userId}) async {
    return dismissed[userId] ?? false;
  }

  @override
  Future<void> setOrientationDismissed({required String userId}) async {
    dismissed[userId] = true;
  }

  @override
  Future<void> resetFirstRunState({required String userId}) async {
    activated.remove(userId);
    dismissed.remove(userId);
  }

  @override
  Future<OrientationDebugOverride> getDebugOverride() async => debugOverride;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {
    debugOverride = value;
  }
}

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _bindAndHydrate(
  HomeActivationCubit cubit,
  String accountId,
) async {
  await cubit.bindAccount(accountId);
  await _settle();
}

void _reportSettledEmpty(HomeActivationCubit cubit, String accountId) {
  cubit.reportMyWork(
    accountId: accountId,
    myWorkCardCount: 0,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );
  cubit.reportInbox(
    accountId: accountId,
    inboxItemCount: 0,
    inboxLoaded: true,
    inboxFailed: false,
  );
}

void main() {
  late _FakePreferences preferences;
  late HomeActivationCubit cubit;

  setUp(() {
    preferences = _FakePreferences();
    cubit = HomeActivationCubit(preferences);
  });

  tearDown(() async {
    await cubit.close();
  });

  test('undecided until hydrated', () async {
    final bind = cubit.bindAccount('U1');
    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.undecided,
    );
    await bind;
    await _settle();
    expect(cubit.state.hydrated, isTrue);
  });

  test(
    'undecided while My Work is loaded and Inbox is neither loaded nor failed',
    () async {
      await _bindAndHydrate(cubit, 'U1');
      cubit.reportMyWork(
        accountId: 'U1',
        myWorkCardCount: 0,
        draftCount: 0,
        archivedCountHint: 0,
        myWorkLoaded: true,
      );

      expect(
        cubit.state.decideFor(MyWorkFilter.active),
        OrientationDecision.undecided,
      );
    },
  );

  test('ordinaryEmpty when inboxFailed', () async {
    await _bindAndHydrate(cubit, 'U1');
    cubit.reportMyWork(
      accountId: 'U1',
      myWorkCardCount: 0,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );
    cubit.reportInbox(
      accountId: 'U1',
      inboxItemCount: 0,
      inboxLoaded: false,
      inboxFailed: true,
    );

    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.ordinaryEmpty,
    );
  });

  test('show on a settled-empty snapshot', () async {
    await _bindAndHydrate(cubit, 'U1');
    _reportSettledEmpty(cubit, 'U1');

    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.show,
    );
  });

  test('writes activation latch exactly once on hasProvenActivity', () async {
    await _bindAndHydrate(cubit, 'U1');
    cubit.reportMyWork(
      accountId: 'U1',
      myWorkCardCount: 1,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );
    cubit.reportMyWork(
      accountId: 'U1',
      myWorkCardCount: 2,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );

    expect(cubit.state.activatedLatch, isTrue);
    expect(preferences.setActivatedCalls, 1);
    await _settle();
    expect(preferences.setActivatedCalls, 1);
  });

  test(
    'writes activation latch when My Work proves activity during Inbox outage',
    () async {
      await _bindAndHydrate(cubit, 'U1');
      cubit.reportMyWork(
        accountId: 'U1',
        myWorkCardCount: 1,
        draftCount: 0,
        archivedCountHint: 0,
        myWorkLoaded: true,
      );

      expect(cubit.state.activatedLatch, isTrue);
      expect(preferences.setActivatedCalls, 1);
      expect(cubit.state.signals.isSettled, isFalse);
      expect(
        cubit.state.decideFor(MyWorkFilter.active),
        OrientationDecision.ordinaryEmpty,
      );
    },
  );

  test('dismiss suppresses without writing activation latch', () async {
    await _bindAndHydrate(cubit, 'U1');
    _reportSettledEmpty(cubit, 'U1');
    await cubit.dismiss();
    await _settle();

    expect(cubit.state.dismissedLatch, isTrue);
    expect(preferences.setActivatedCalls, 0);
    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.ordinaryEmpty,
    );
  });

  test('ignores reports tagged with a non-bound account', () async {
    await _bindAndHydrate(cubit, 'U1');
    cubit.reportMyWork(
      accountId: 'OTHER',
      myWorkCardCount: 5,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );

    expect(cubit.state.signals.myWorkLoaded, isFalse);
    expect(preferences.setActivatedCalls, 0);
  });

  test('rebinding mid-flight discards stale preference read', () async {
    preferences.activated['A'] = true;
    preferences.activated['B'] = false;
    final delay = Completer<bool>();
    preferences.activatedReadDelayUserId = 'A';
    preferences.activatedReadDelay = delay;

    unawaited(cubit.bindAccount('A'));
    await _settle(2);
    await cubit.bindAccount('B');
    delay.complete(true);
    await _settle();

    expect(cubit.state.boundAccountId, 'B');
    expect(cubit.state.activatedLatch, isFalse);
    expect(cubit.state.hydrated, isTrue);
  });

  test("unbinding to '' reaches a stable non-show decision", () async {
    await _bindAndHydrate(cubit, 'U1');
    _reportSettledEmpty(cubit, 'U1');
    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.show,
    );

    await cubit.bindAccount('');
    await _settle();

    expect(cubit.state.hydrated, isTrue);
    expect(cubit.state.boundAccountId, isEmpty);
    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.ordinaryEmpty,
    );
  });

  test('show override wins over both latches', () async {
    preferences.activated['U1'] = true;
    preferences.dismissed['U1'] = true;
    preferences.debugOverride = OrientationDebugOverride.show;
    await _bindAndHydrate(cubit, 'U1');

    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.show,
    );
  });

  test('hide override wins over an eligible account', () async {
    await _bindAndHydrate(cubit, 'U1');
    _reportSettledEmpty(cubit, 'U1');
    await cubit.setDebugOverride(OrientationDebugOverride.hide);

    expect(
      cubit.state.decideFor(MyWorkFilter.active),
      OrientationDecision.ordinaryEmpty,
    );
  });

  test('show override still persists activation when activity is proven', () async {
    preferences.debugOverride = OrientationDebugOverride.show;
    await _bindAndHydrate(cubit, 'U1');
    cubit.reportMyWork(
      accountId: 'U1',
      myWorkCardCount: 1,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );

    expect(preferences.setActivatedCalls, 1);
    expect(cubit.state.activatedLatch, isTrue);
  });

  test('hide override still persists activation when activity is proven', () async {
    preferences.debugOverride = OrientationDebugOverride.hide;
    await _bindAndHydrate(cubit, 'U1');
    cubit.reportInbox(
      accountId: 'U1',
      inboxItemCount: 1,
      inboxLoaded: true,
      inboxFailed: false,
    );

    expect(preferences.setActivatedCalls, 1);
    expect(cubit.state.activatedLatch, isTrue);
  });

  test('no override shows the panel for a non-active filter', () {
    const settledEmpty = HomeActivationState(
      hydrated: true,
      boundAccountId: 'U1',
      signals: const HomeActivationSignals(
        myWorkLoaded: true,
        inboxLoaded: true,
      ),
    );

    for (final override in OrientationDebugOverride.values) {
      final state = settledEmpty.copyWith(debugOverride: override);
      for (final filter in MyWorkFilter.values) {
        if (filter == MyWorkFilter.active) continue;
        expect(
          state.decideFor(filter),
          OrientationDecision.ordinaryEmpty,
          reason: '$override / $filter',
        );
      }
    }
  });
}
