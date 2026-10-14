import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
      child: Scaffold(body: child),
    ),
  );
}

TimelineHelpOffer _helpOffer({
  required String userId,
  String? helpType,
  String? roleLabel,
  String message = '',
  bool isWithdrawn = false,
  DateTime? authorSeenAt,
  CoordinationResponseType? coordinationResponse,
  int? roomAccess,
  HelpOfferAdmissionAction? admissionAction,
  String? lastDeclineReason,
  String? lastRemoveReason,
  int offerKind = 0,
}) {
  final t = DateTime.utc(2025);
  return TimelineHelpOffer(
    user: Profile(id: userId, displayName: 'Help Offerer'),
    message: message,
    createdAt: t,
    updatedAt: t,
    helpType: helpType,
    roleLabel: roleLabel,
    isWithdrawn: isWithdrawn,
    coordinationResponse: coordinationResponse,
    roomAccess: roomAccess,
    admissionAction: admissionAction,
    lastDeclineReason: lastDeclineReason,
    lastRemoveReason: lastRemoveReason,
    offerKind: offerKind,
    authorSeenAt: authorSeenAt,
  );
}

/// B024 — Accept / Decline on a help offer must be buttons that carry their
/// own name: the node with the tap action is what a screen reader announces
/// and what web exposes as `role=button`.
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

  testWidgets('Accept and Decline are named, tappable buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var accepted = 0;
    var declined = 0;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: HelpOfferTile(
            helpOffer: _helpOffer(userId: 'c1', message: 'I can help'),
            beaconId: 'B1',
            beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
            beaconAuthorId: 'auth',
            isAuthorView: true,
            showBackupHint: false,
            onAccept: () => accepted++,
            onDecline: () => declined++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['Accept', 'Decline']) {
      expect(
        find.semantics.byLabel(label),
        findsOne,
        reason: '$label should be one semantics node',
      );
      expect(
        find.semantics.byLabel(label).evaluate().single,
        isSemantics(
          label: label,
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
    }

    tester.semantics
      ..tap(find.semantics.byLabel('Accept'))
      ..tap(find.semantics.byLabel('Decline'));
    await tester.pump();
    expect(accepted, 1);
    expect(declined, 1);
    handle.dispose();
  });
}
