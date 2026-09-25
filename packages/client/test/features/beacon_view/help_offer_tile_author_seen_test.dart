import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
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

const _notSeen = 'Sent · not seen by the author yet';
const _seen = 'Seen by the author · awaiting decision';

Widget _tile({
  required TimelineHelpOffer offer,
  bool isMine = false,
  bool isAuthorView = false,
  bool showBackupHint = true,
}) => HelpOfferTile(
  helpOffer: offer,
  beaconId: 'B1',
  beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
  beaconAuthorId: 'auth',
  isMine: isMine,
  isAuthorView: isAuthorView,
  showBackupHint: showBackupHint,
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

  testWidgets('own pending offer, not seen: text and Icons.done', (t) async {
    await t.pumpWidget(
      _wrap(_tile(offer: _helpOffer(userId: 'me'), isMine: true)),
    );
    await t.pumpAndSettle();

    expect(find.text(_notSeen), findsOneWidget);
    expect(find.byIcon(Icons.done), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsNothing);
    final icon = t.widget<Icon>(find.byIcon(Icons.done));
    expect(icon.size, 12);
    expect(icon.color, TenturaTokens.light.textMuted);
    expect(
      t.widget<Text>(find.text(_notSeen)).style?.color,
      TenturaTokens.light.textMuted,
    );
  });

  testWidgets('own pending offer, seen: text, Icons.done_all, tooltip', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            authorSeenAt: DateTime.utc(2025, 1, 2, 3, 4),
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(_seen), findsOneWidget);
    expect(find.text(_notSeen), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
    final icon = t.widget<Icon>(find.byIcon(Icons.done_all));
    expect(icon.size, 12);
    expect(icon.color, TenturaTokens.light.info);
    expect(
      t.widget<Text>(find.text(_seen)).style?.color,
      TenturaTokens.light.textMuted,
    );
    final seenAt = DateTime.utc(2025, 1, 2, 3, 4).toLocal();
    final when = '${dateFormatYMD(seenAt)} · ${timeFormatHm(seenAt)}';
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Seen $when',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == _seen,
      ),
      findsOneWidget,
    );
  });

  testWidgets('declined own offer shows decision, no author-seen row', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            admissionAction: HelpOfferAdmissionAction.decline,
            lastDeclineReason: 'Wrong fit',
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Declined: Wrong fit'), findsOneWidget);
    expect(find.text(_notSeen), findsNothing);
    expect(find.text(_seen), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('removed own offer shows decision, no author-seen row', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            admissionAction: HelpOfferAdmissionAction.remove,
            lastRemoveReason: 'No longer needed',
            authorSeenAt: DateTime.utc(2025, 1, 2),
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.textContaining('No longer needed'), findsOneWidget);
    expect(find.text(_notSeen), findsNothing);
    expect(find.text(_seen), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('pending own backup offer shows the row', (t) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(userId: 'me', offerKind: 1),
          isMine: true,
          showBackupHint: false,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(_notSeen), findsOneWidget);
    expect(find.byIcon(Icons.done), findsOneWidget);
  });

  testWidgets('pending own backup offer with hint shows the row too', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            offerKind: 1,
            authorSeenAt: DateTime.utc(2025, 1, 2),
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(_seen), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('author viewing someone else offer sees no row', (t) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'c1',
            authorSeenAt: DateTime.utc(2025, 1, 2),
          ),
          isAuthorView: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(_notSeen), findsNothing);
    expect(find.text(_seen), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('row sits in the footer below the message', (t) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(userId: 'me', message: 'I can drive'),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    final row = t.getTopLeft(find.text(_notSeen)).dy;
    expect(row, greaterThan(t.getBottomLeft(find.text('I can drive')).dy));
    final divider = t.getBottomLeft(find.byType(TenturaHairlineDivider).last);
    expect(
      divider.dy,
      greaterThan(t.getBottomLeft(find.text('I can drive')).dy),
    );
    expect(row, greaterThanOrEqualTo(divider.dy));
  });

  testWidgets('backup row sits beneath the hint', (t) async {
    final l10n = lookupL10n(const Locale('en'));
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            offerKind: 1,
            message: 'Standing by',
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    final row = t.getTopLeft(find.text(_notSeen)).dy;
    expect(
      row,
      greaterThan(t.getBottomLeft(find.text(l10n.helpOfferBackupHintMine)).dy),
    );
    expect(row, lessThan(t.getTopLeft(find.text('Standing by')).dy));
  });

  testWidgets('backup row sits beneath the badge when hint is off', (t) async {
    final l10n = lookupL10n(const Locale('en'));
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(userId: 'me', offerKind: 1),
          isMine: true,
          showBackupHint: false,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(
      t.getTopLeft(find.text(_notSeen)).dy,
      greaterThan(t.getBottomLeft(find.text(l10n.helpOfferBackupBadge)).dy),
    );
  });

  for (final kind in [0, 1]) {
    testWidgets('admitted own offer (kind $kind) has no row', (t) async {
      await t.pumpWidget(
        _wrap(
          _tile(
            offer: _helpOffer(
              userId: 'me',
              offerKind: kind,
              roomAccess: RoomAccessBits.admitted,
              admissionAction: HelpOfferAdmissionAction.accept,
              authorSeenAt: DateTime.utc(2025, 1, 2),
            ),
            isMine: true,
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text(_notSeen), findsNothing);
      expect(find.text(_seen), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('withdrawn own offer (kind $kind) has no row', (t) async {
      await t.pumpWidget(
        _wrap(
          _tile(
            offer: _helpOffer(userId: 'me', offerKind: kind, isWithdrawn: true),
            isMine: true,
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text(_notSeen), findsNothing);
      expect(find.text(_seen), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });
  }

  testWidgets('declined own backup offer shows decision, no row', (t) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            offerKind: 1,
            admissionAction: HelpOfferAdmissionAction.decline,
            lastDeclineReason: 'Wrong fit',
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Declined: Wrong fit'), findsOneWidget);
    expect(find.text(_notSeen), findsNothing);
    expect(find.text(_seen), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('removed own backup offer shows decision, no row', (t) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            offerKind: 1,
            admissionAction: HelpOfferAdmissionAction.remove,
            lastRemoveReason: 'No longer needed',
            authorSeenAt: DateTime.utc(2025, 1, 2),
          ),
          isMine: true,
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.textContaining('No longer needed'), findsOneWidget);
    expect(find.text(_notSeen), findsNothing);
    expect(find.text(_seen), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('row renders Russian copy and tooltip under ru locale', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        _tile(
          offer: _helpOffer(
            userId: 'me',
            authorSeenAt: DateTime.utc(2025, 1, 2, 3, 4),
          ),
          isMine: true,
        ),
        locale: const Locale('ru'),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Автор видел · ждём решения'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Просмотрено '),
      ),
      findsOneWidget,
    );
  });
}
