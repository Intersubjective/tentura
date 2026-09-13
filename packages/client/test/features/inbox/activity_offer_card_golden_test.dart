import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_card.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _GoldenInboxCubit extends Mock implements InboxCubit {}

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final class _GoldenSetupCase implements InviteAcceptedSetupPort {
  static const profile = Profile(
    id: 'invitee-1',
    displayName: 'Carol',
    handle: 'carol',
  );

  static const prompt = InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: 'invitee-1',
    state: PromptStateValue.pending,
  );

  @override
  Future<Profile> fetchProfile(String subjectId) async => profile;

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) async => prompt;

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) async {}

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) async {}

  @override
  Future<void> skip(String subjectId) async {}

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async =>
      {};
}

InboxItem _forwardItem({required bool allowsOfferHelp}) {
  final at = DateTime.utc(2026, 6, 20, 9, 15);
  return InboxItem(
    beaconId: 'beacon-offer-1',
    latestForwardAt: at,
    provenance: const InboxProvenance(
      senders: [
        InboxForwardSender(
          id: 'fwd-anna',
          displayName: 'Anna',
          mr: 1.0,
        ),
      ],
      totalDistinctSenders: 3,
      strongestNotePreview: '',
    ),
    status: allowsOfferHelp
        ? InboxItemStatus.needsMe
        : InboxItemStatus.rejected,
    beacon: Beacon(
      id: 'beacon-offer-1',
      title: 'Garden cleanup this weekend',
      description: 'Need help clearing weeds and trimming hedges.',
      author: const Profile(id: 'auth', displayName: 'Alex'),
      createdAt: at,
      updatedAt: at,
    ),
  );
}

AttentionReceipt _promptReceipt() => AttentionReceipt(
  id: 'receipt-prompt-1',
  category: 'connections',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: 'Carol · @carol',
  body: 'Joined via your invitation. You are now connected.',
  actionUrl: '/profile/view/invitee-1',
  createdAt: DateTime.utc(2026, 6, 20, 11, 0),
  collapsedCount: 1,
  presentationKey: 'invite_accepted',
  presentationPayloadJson: '{"inviteOrigin":"new_account"}',
  surface: AttentionSurface.activity,
  actorUserId: 'invitee-1',
  targetEntityId: 'invitee-1',
);

Future<void> _pumpForwardGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required bool allowsOfferHelp,
  required bool showUnseenDot,
  TextScaler? textScaler,
  required String goldenName,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _GoldenInboxCubit();

  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _GoldenProfileCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: brightness == Brightness.light
            ? TenturaTheme.light()
            : TenturaTheme.dark(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const Key('golden'),
                  child: SizedBox(
                    width: size.width,
                    child: ActivityOfferCard.forward(
                      item: _forwardItem(allowsOfferHelp: allowsOfferHelp),
                      inboxCubit: cubit,
                      showUnseenDot: showUnseenDot,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

Future<void> _pumpPromptGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  TextScaler? textScaler,
  required String goldenName,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: brightness == Brightness.light
          ? TenturaTheme.light()
          : TenturaTheme.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler ?? TextScaler.noScaling,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: ActivityOfferCard.prompt(
                    receipt: _promptReceipt(),
                    promptProjection: const PromptProjection.known(
                      _GoldenSetupCase.prompt,
                    ),
                    setupCase: _GoldenSetupCase(),
                    onTap: () {},
                    onMarkSeen: () async {},
                    onMarkUnseen: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void main() {
  const width = 360.0;
  const height = 220.0;
  const size = Size(width, height);

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'light' : 'dark';
    for (final locale in const [Locale('en'), Locale('ru')]) {
      final lang = locale.languageCode;

      testWidgets(
        'forward offer card with offer-help $theme $lang',
        (tester) async {
          await _pumpForwardGolden(
            tester,
            size: size,
            locale: locale,
            brightness: brightness,
            allowsOfferHelp: true,
            showUnseenDot: true,
            goldenName:
                'activity_offer_card_forward_with_help_${theme}_$lang.png',
          );
        },
      );

      testWidgets(
        'forward offer card without offer-help $theme $lang',
        (tester) async {
          await _pumpForwardGolden(
            tester,
            size: size,
            locale: locale,
            brightness: brightness,
            allowsOfferHelp: false,
            showUnseenDot: true,
            goldenName:
                'activity_offer_card_forward_no_help_${theme}_$lang.png',
          );
        },
      );

      testWidgets(
        'prompt offer card $theme $lang',
        (tester) async {
          await _pumpPromptGolden(
            tester,
            size: size,
            locale: locale,
            brightness: brightness,
            goldenName: 'activity_offer_card_prompt_${theme}_$lang.png',
          );
        },
      );
    }
  }

  testWidgets('forward offer card height bound at 1.3x text scale', (
    tester,
  ) async {
    await _pumpForwardGolden(
      tester,
      size: size,
      locale: const Locale('en'),
      brightness: Brightness.light,
      allowsOfferHelp: true,
      showUnseenDot: true,
      textScaler: const TextScaler.linear(1.3),
      goldenName: 'activity_offer_card_forward_with_help_light_en_1p3x.png',
    );
    final box = tester.renderObject<RenderBox>(find.byKey(const Key('golden')));
    expect(box.size.height, lessThanOrEqualTo(180));
  });
}
