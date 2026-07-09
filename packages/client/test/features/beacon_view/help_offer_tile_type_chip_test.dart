import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

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

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: Scaffold(body: child),
    ),
  );
}

TimelineHelpOffer _helpOffer({
  required String userId,
  String? helpType,
  String message = '',
  bool isWithdrawn = false,
  CoordinationResponseType? coordinationResponse,
  int? roomAccess,
  HelpOfferAdmissionAction? admissionAction,
  String? lastDeclineReason,
  String? lastRemoveReason,
}) {
  final t = DateTime.utc(2025);
  return TimelineHelpOffer(
    user: Profile(id: userId, displayName: 'Help Offerer'),
    message: message,
    createdAt: t,
    updatedAt: t,
    helpType: helpType,
    isWithdrawn: isWithdrawn,
    coordinationResponse: coordinationResponse,
    roomAccess: roomAccess,
    admissionAction: admissionAction,
    lastDeclineReason: lastDeclineReason,
    lastRemoveReason: lastRemoveReason,
  );
}

void main() {
  late _FakePlatformRepository platform;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('helpOfferTypeSlugs parses JSON array or single slug', () {
    expect(helpOfferTypeSlugs('["money","time"]'), ['money', 'time']);
    expect(helpOfferTypeSlugs('money'), ['money']);
    expect(helpOfferTypeSlugs('  '), isEmpty);
    expect(helpOfferTypeSlugs(null), isEmpty);
  });

  testWidgets('known help_type renders read-only RawChip with l10n label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(userId: 'c1', helpType: 'money'),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(RawChip, 'Money'), findsOneWidget);
    final chip = tester.widget<RawChip>(
      find.widgetWithText(RawChip, 'Money'),
    );
    expect(chip.onPressed, isNull);
  });

  testWidgets('unknown help_type wire renders plain RawChip label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(userId: 'c1', helpType: 'legacy_unknown_key'),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(
      find.widgetWithText(RawChip, 'legacy_unknown_key'),
      findsOneWidget,
    );
  });

  testWidgets('JSON-encoded help_type array renders one chip per slug', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(
            userId: 'c1',
            helpType: '["money","time"]',
          ),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(RawChip, 'Money'), findsOneWidget);
    expect(find.widgetWithText(RawChip, 'Time'), findsOneWidget);
    expect(find.byType(RawChip), findsNWidgets(2));
  });

  testWidgets('null help_type hides capability row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(userId: 'c1'),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(RawChip), findsNothing);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('withdrawn help offer shows Withdrawn, not Active', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(userId: 'c1', isWithdrawn: true),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets(
    'viewer help offer shows You in primary accent, no mine row',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HelpOfferTile(
            helpOffer: _helpOffer(userId: 'me'),
            beaconId: 'B1',
            beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
            beaconAuthorId: 'auth',
            isMine: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(find.text('mine'), findsNothing);
      final theme = Theme.of(tester.element(find.text('You')));
      final text = tester.widget<Text>(find.text('You'));
      expect(text.style?.color, theme.colorScheme.primary);
      expect(text.style?.fontWeight, FontWeight.w600);
    },
  );

  testWidgets('author view pending review shows accept and decline actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(userId: 'c1'),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
          isAuthorView: true,
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Set coordination signal'), findsNothing);
  });

  testWidgets('committer sees declined reason without actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(
            userId: 'me',
            admissionAction: HelpOfferAdmissionAction.decline,
            lastDeclineReason: 'Wrong fit',
          ),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
          isMine: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Declined: Wrong fit'), findsOneWidget);
    final text = tester.widget<Text>(
      find.text('Declined: Wrong fit'),
    );
    expect(text.style?.color, TenturaTokens.light.danger);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('message link opens via launchUserLink', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HelpOfferTile(
          helpOffer: _helpOffer(
            userId: 'c1',
            message: 'See https://example.com for details',
          ),
          beaconId: 'B1',
          beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTextFinder = find
        .descendant(
          of: find.byType(ShowMoreText),
          matching: find.byType(RichText),
        )
        .first;
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

    expect(platform.launchedUserLink, Uri.parse('https://example.com'));
  });
}
