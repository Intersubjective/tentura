import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

BeaconCreateCubit _createCubit(FakeBeaconWritePort write) => BeaconCreateCubit(
  beaconCreateCase: fakeBeaconCreateCase(write: write),
  effects: FakeUiEffectPort(),
);

void _fillRequired(BeaconCreateCubit cubit) {
  cubit
    ..setTitle('Need a piano moved')
    ..setDescription('Two flights of stairs, this weekend.');
}

ForwardCubit _embeddedForward(String beaconId) {
  final forward = ForwardCubit(
    beaconId: beaconId,
    embedded: true,
    debugSkipInitialLoad: true,
    debugInitialState: ForwardState(
      beaconId: beaconId,
      candidates: [
        ForwardCandidate(
          profile: const Profile(
            id: 'U1',
            displayName: 'Recipient',
            myVote: 1,
            subjectExplicitlyTrustsViewer: true,
          ),
        ),
      ],
    ),
    effects: FakeUiEffectPort(),
  );
  forward.toggleSelection('U1');
  return forward;
}

/// Mirrors [BeaconCreateScreen] app bar title selection (draft vs live).
class _CreateTitleProbe extends StatelessWidget {
  const _CreateTitleProbe();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
      builder: (context, state) {
        final title = state.isEditMode
            ? l10n.editBeaconTitle
            : state.isLive
            ? l10n.liveRequestTitle
            : state.draftId != null
            ? l10n.editDraftTitle
            : l10n.createNewBeacon;
        return Text(title, textDirection: TextDirection.ltr);
      },
    );
  }
}

class _HarnessRouter extends Mock implements StackRouter {
  int popAndPushCount = 0;
  PageRouteInfo? lastPopAndPush;

  @override
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) async {
    popAndPushCount++;
    lastPopAndPush = route;
    return null;
  }
}

void main() {
  group('issue #148 after send leaves draft editor', () {
    test(
      'sendRequest from draft publishes and marks create session live',
      () async {
        final write = FakeBeaconWritePort(
          beacon: Beacon.empty.copyWith(id: 'B148', status: BeaconStatus.draft),
        );
        final cubit = _createCubit(write);
        addTearDown(cubit.close);
        _fillRequired(cubit);
        await cubit.ensureDraft(context: 'c', showMessage: false);

        final forward = _embeddedForward('B148');
        addTearDown(forward.close);

        await cubit.sendRequest(context: 'c', forwardCubit: forward);

        expect(write.publishedIds, ['B148']);
        expect(
          cubit.state.isLive,
          isTrue,
          reason:
              'After publish+send, session must leave draft editor (like makeLive)',
        );
        expect(cubit.state.isEditMode, isFalse);
      },
    );

    testWidgets(
      'after sendRequest app bar title is live request not edit draft',
      (tester) async {
        final write = FakeBeaconWritePort(
          beacon: Beacon.empty.copyWith(id: 'B148', status: BeaconStatus.draft),
        );
        final cubit = _createCubit(write);
        addTearDown(cubit.close);
        _fillRequired(cubit);
        await cubit.ensureDraft(context: 'c', showMessage: false);

        final forward = _embeddedForward('B148');
        addTearDown(forward.close);

        await cubit.sendRequest(context: 'c', forwardCubit: forward);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: BlocProvider<BeaconCreateCubit>.value(
              value: cubit,
              child: const _CreateTitleProbe(),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Edit draft'), findsNothing);
        expect(find.text('Live request'), findsOneWidget);
      },
    );

    test(
      'successful send should open live beacon view like makeLive',
      () async {
        final router = _HarnessRouter();
        await popCreateAndOpenLiveBeacon(router, beaconId: 'B148');

        expect(router.popAndPushCount, 1);
        expect(router.lastPopAndPush, isA<BeaconViewRoute>());
        final route = router.lastPopAndPush! as BeaconViewRoute;
        expect(route.args!.id, 'B148');
      },
    );

    test(
      '_sendRequest navigates to live request after successful delivery',
      () {
        final screenPath = File(
          'lib/features/beacon_create/ui/screen/beacon_create_screen.dart',
        );
        expect(
          screenPath.existsSync(),
          isTrue,
          reason: 'Run from packages/client',
        );
        final src = screenPath.readAsStringSync();
        final sendStart = src.indexOf('Future<void> _sendRequest()');
        final sendEnd = src.indexOf('Future<void> _leaveForm()', sendStart);
        expect(sendStart, greaterThan(0));
        expect(sendEnd, greaterThan(sendStart));
        final sendBody = src.substring(sendStart, sendEnd);

        expect(
          sendBody,
          contains('popCreateAndOpenLiveBeacon'),
          reason:
              'Issue #148: after send, leave create for BeaconViewRoute '
              '(parity with _makeLive)',
        );
        expect(
          sendBody,
          isNot(contains('maybePop')),
          reason: 'maybePop leaves user on draft create surface',
        );
      },
    );
  });
}
