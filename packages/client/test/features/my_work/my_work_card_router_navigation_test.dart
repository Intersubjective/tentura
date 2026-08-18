import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    return null;
  }
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

void main() {
  testWidgets('tapping a My Work card pushes a routed BeaconViewRoute', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b-my-work-nav',
      title: 'My Work nav request',
      author: const Profile(id: 'author', displayName: 'Author'),
      helpOfferCount: 1,
    );
    final vm = MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedActive,
      beacon: beacon,
      offerHelpMessage: 'I can help',
    );
    final router = _HarnessRouter();

    await tester.pumpWidget(
      StackRouterScope(
        controller: router,
        stateHash: 0,
        child: BlocProvider<ProfileCubit>.value(
          value: _TestProfileCubit(),
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: MyWorkCardRouter(vm: vm),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('My Work nav request'));
    await tester.pump();

    expect(router.pushCount, 1);
    final push = router.lastPush;
    expect(push, isA<BeaconViewRoute>());
    final args = (push! as BeaconViewRoute).args!;
    expect(args.id, 'b-my-work-nav');
    expect(args.entry, kBeaconEntryMyWork);
  });
}
