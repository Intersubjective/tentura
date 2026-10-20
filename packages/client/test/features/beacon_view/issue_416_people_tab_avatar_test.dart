// #416: on the People tab a helper's avatar reads "<Name>, open profile",
// not the initials.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _author = Profile(id: 'auth', displayName: 'Author');

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

HelpOfferTile _tile() {
  final t = DateTime.utc(2025);
  return HelpOfferTile(
    helpOffer: TimelineHelpOffer(
      user: const Profile(id: 'u-help', displayName: 'Help Offerer'),
      message: 'I can bring a van',
      createdAt: t,
      updatedAt: t,
    ),
    beaconId: 'B1',
    beaconAuthor: _author,
    beaconAuthorId: _author.id,
  );
}

SemanticsFinder _namedTapNode(String name) => find.semantics.byPredicate(
  (node) =>
      !node.isMergedIntoParent &&
      node.getSemanticsData().label.contains(name) &&
      node.getSemanticsData().hasAction(SemanticsAction.tap),
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('a helper avatar reads <Name>, open profile, not the initials', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_tile()));
    await tester.pumpAndSettle();

    expect(
      _namedTapNode('Help Offerer, open profile'),
      findsOne,
      reason: spokenNodes().join(' | '),
    );
    expect(spokenLines(), isNot(contains('HO')));
    handle.dispose();
  });

  testWidgets('the helper avatar name is localized', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_tile(), locale: const Locale('ru')));
    await tester.pumpAndSettle();

    expect(
      _namedTapNode('Help Offerer, открыть профиль'),
      findsOne,
      reason: spokenNodes().join(' | '),
    );
    expect(spokenLines(), isNot(contains('HO')));
    handle.dispose();
  });
}
