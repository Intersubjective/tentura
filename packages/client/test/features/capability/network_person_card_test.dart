import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _FakeProfileCubit implements ProfileCubit {
  _FakeProfileCubit(Profile profile) : _state = ProfileState(profile: profile);

  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => Stream.value(_state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePresenceCubit implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => Stream.value(state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({
  required Profile profile,
  Profile viewer = const Profile(id: 'me', displayName: 'Me'),
}) {
  return MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit(viewer)),
            BlocProvider<PresenceCubit>.value(value: _FakePresenceCubit()),
            BlocProvider(create: (_) => ScreenCubit.local()),
          ],
          child: Scaffold(body: NetworkPersonCard(profile: profile)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows nickname, then canonical, then trust', (tester) async {
    await tester.pumpWidget(
      _wrap(
        profile: const Profile(
          id: 'U-peer',
          contactName: 'Mom',
          displayName: 'Alice',
          handle: 'alice',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Alice · @alice'), findsOneWidget);
    expect(find.textContaining('Trust:'), findsOneWidget);
  });

  testWidgets('peer with empty shownName uses noName', (tester) async {
    await tester.pumpWidget(
      _wrap(
        profile: const Profile(id: 'U-peer', handle: 'alice'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No name'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
  });

  testWidgets('self row uses You and skips trust', (tester) async {
    const me = Profile(id: 'me', displayName: 'Ada', handle: 'ada');
    await tester.pumpWidget(_wrap(profile: me, viewer: me));
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining('Trust:'), findsNothing);
    expect(find.text('@ada'), findsOneWidget);
  });
}
