import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/ui/widget/profile_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  Uri? launchedUserLink;

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {
    launchedUserLink = uri;
  }
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  _TestProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _harness({
  required Profile profile,
  required ProfileCubit profileCubit,
  TargetPlatform? platform,
}) {
  return MaterialApp(
    theme: TenturaTheme.light().copyWith(
      platform: platform ?? TargetPlatform.android,
    ),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: TenturaResponsiveScope(
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ScreenCubit>(
            create: (_) => ScreenCubit(FakeUiEffectPort()),
          ),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
        ],
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              ProfileBody(
                profile: profile,
                profileCubit: profileCubit,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _FakePlatformRepository platform;
  late Profile profile;
  late _TestProfileCubit profileCubit;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
    profile = const Profile(
      id: 'U-me',
      displayName: 'Ada',
      description: 'Visit https://example.com/path for more.',
    );
    profileCubit = _TestProfileCubit(profile);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('profile description link opens URL', (tester) async {
    await tester.pumpWidget(
      _harness(profile: profile, profileCubit: profileCubit),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('https://'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderParagraph =
        tester.element(richTextFinder).renderObject! as RenderParagraph;
    final text = richText.text.toPlainText();
    final linkStart = text.indexOf('https://');
    final boxes = renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: linkStart, extentOffset: linkStart + 1),
    );
    final point = renderParagraph.localToGlobal(boxes.first.toRect().center);

    await tester.tapAt(point);
    await tester.pumpAndSettle();

    expect(
      platform.launchedUserLink,
      Uri.parse('https://example.com/path'),
    );
  });

  testWidgets('macOS theme wraps description in SelectionArea', (tester) async {
    await tester.pumpWidget(
      _harness(
        profile: profile,
        profileCubit: profileCubit,
        platform: TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
  });
}
