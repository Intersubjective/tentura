import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

// #454: on the Forward screen, "Invite new person" created the invite before
// the dialog opened, so just opening and closing the dialog (no Copy, no
// Share) left an unused invite behind, and the "Invite saved" bar appeared
// anyway.
//
// Rule: the invite is kept whenever it was copied, shared, or its QR was ever
// on screen (someone may have scanned it); it is discarded — silently, with
// no bar — only when the dialog closes with none of those. When kept, the
// "Invite saved" bar shows and goes away on its own (#470).

const _inviteSaved = 'Invite saved — find it in the Invitations tab';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// Keeps the server-side truth: which invites exist after the flow.
class _InvitationServerFake extends Fake implements InvitationRepository {
  final live = <String>{};
  final created = <String>[];
  final deleted = <String>[];

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: live.length,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async {
    final id = 'Iabc123def45${created.length}';
    created.add(id);
    live.add(id);
    return InvitationEntity(
      id: id,
      beaconId: beaconId,
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
  }

  @override
  Future<void> deleteById(String id) async {
    deleted.add(id);
    live.remove(id);
  }

  @override
  Future<void> dispose() async {}
}

ForwardCubit _forwardCubitWithBeacon() {
  final cubit = ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  final beacon = Beacon.empty.copyWith(
    id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
    title: 'Test beacon',
    context: 'General',
    viewerCanForward: true,
    startAt: DateTime.utc(2025, 5, 12),
    endAt: DateTime.utc(2025, 5, 19),
  );
  cubit.emit(
    ForwardState(
      beaconId: 'b1',
      beacon: beacon,
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Clara',
            rScore: 1,
            score: 70,
          ),
        ),
      ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
  return cubit;
}

/// Answers `Clipboard.setData` like a browser that allows the write.
void _mockClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(ShareCodeDialog), matching: matching);

Finder get _closeButton => _inDialog(find.widgetWithText(TextButton, 'Close'));

/// share_plus's platform channel (MethodChannelShare.channel).
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

/// Answers the system share sheet as if the person shared the link; returns
/// the list of share calls seen.
List<MethodCall> _mockShareSheetSuccess(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _shareChannel,
    (call) async {
      calls.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      null,
    ),
  );
  return calls;
}

Finder get _inviteSavedBar => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(_inviteSaved, findRichText: true),
);

class _Harness {
  _Harness(this.server, this.effects);

  final _InvitationServerFake server;
  final FakeUiEffectPort effects;
}

const _desktop = Size(1280, 800);
const _phone = Size(390, 844);

/// Opens Forward at [size] (default: the issue viewport, desktop 1280x800 =
/// link-first dialog, QR behind "Show QR code"; 390x844 = compact, QR first),
/// taps "Invite new person" and waits for the share dialog.
Future<_Harness> _openInviteDialog(
  WidgetTester tester, {
  Size size = _desktop,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final server = _InvitationServerFake();
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<InvitationRepository>(server)
    ..registerSingleton<UiEffectPort>(effects);
  addTearDown(GetIt.I.reset);

  final cubit = _forwardCubitWithBeacon();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: snackbarKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ForwardCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        ],
        child: const ForwardBeaconPage(beaconId: 'b1'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Precondition: nothing exists before the person asks for an invite.
  expect(server.live, isEmpty);

  // Fire the bar's own callback (see forward_invite_dialog_copy_test).
  tester.widget<ForwardInviteBar>(find.byType(ForwardInviteBar)).onInvite();

  final shareDialog = find.byType(ShareCodeDialog);
  for (var i = 0; i < 20 && shareDialog.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  expect(shareDialog, findsOneWidget);
  return _Harness(server, effects);
}

/// Taps something inside the dialog (scrolling it into view first).
Future<void> _tapInDialog(WidgetTester tester, String label) async {
  final target = _inDialog(find.text(label));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Closes the dialog with its Close button and settles: any bar raised after
/// it has finished its entrance, and the messenger has armed the bar's
/// timeout. (ScaffoldMessengerState only creates that timer in the build
/// AFTER the entrance animation completes; a single long pump right after
/// the entrance never arms it, so the bar would look like it never leaves.)
Future<void> _closeAndSettle(WidgetTester tester) async {
  await tester.tap(_closeButton);
  await tester.pumpAndSettle();
  expect(find.byType(ShareCodeDialog), findsNothing);
}

/// Selects the whole link text by hand with a mouse drag (desktop), then
/// presses Ctrl+C — the person copies it without the Copy button (#605).
Future<void> _handCopyLink(WidgetTester tester) async {
  final linkText = _inDialog(find.textContaining('/invite/'));
  expect(linkText, findsOneWidget);
  await tester.ensureVisible(linkText);
  await tester.pumpAndSettle();

  final box = tester.getRect(linkText);
  final gesture = await tester.startGesture(
    box.centerLeft + const Offset(1, 0),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(box.centerRight - const Offset(1, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// The person did use the invite: it stays, nothing was deleted, and they
/// are told where to find it.
void _expectKept(_Harness h) {
  expect(
    h.server.live,
    hasLength(1),
    reason:
        'created ${h.server.created}, deleted ${h.server.deleted}: a used '
        'invite must stay saved',
  );
  expect(h.server.deleted, isEmpty);
  expect(_inviteSavedBar, findsOneWidget);
}

/// Unused invite: gone, and the discard is silent (no Invite saved bar, no
/// error bar, no error effect from a failing delete).
void _expectDiscardedSilently(_Harness h) {
  // Net server state, whichever shape the fix takes.
  expect(
    h.server.live,
    isEmpty,
    reason:
        'created ${h.server.created}, deleted ${h.server.deleted}: closing '
        'the dialog must not leave an invite saved',
  );
  expect(_inviteSavedBar, findsNothing);
  expect(find.byType(SnackBar), findsNothing);
  expect(h.effects.emitted.whereType<ShowError>(), isEmpty);
}

void main() {
  testWidgets(
    'Forward invite: Close without Copy or Share leaves no invite and no '
    'Invite saved bar',
    (tester) async {
      final h = await _openInviteDialog(tester);

      await _closeAndSettle(tester);

      _expectDiscardedSilently(h);
    },
  );

  testWidgets(
    'Forward invite: dismissing by tapping outside leaves no invite and no '
    'Invite saved bar',
    (tester) async {
      final h = await _openInviteDialog(tester);

      // Barrier tap, far from the centred dialog (pops with null, not via
      // the Close button).
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCodeDialog), findsNothing);
      _expectDiscardedSilently(h);
    },
  );

  // Negative guard: the fix must not throw away an invite the person copied,
  // and the confirmation still shows then — and goes away on its own (#470).
  testWidgets(
    'Forward invite: Copy then Close keeps the invite and shows a '
    'self-dismissing Invite saved bar',
    (tester) async {
      _mockClipboard(tester);
      final h = await _openInviteDialog(tester);

      await _tapInDialog(tester, 'Copy to clipboard');
      await _closeAndSettle(tester);

      _expectKept(h);

      // Bar fully shown and its timer armed (see _closeAndSettle): it must
      // time out after kSnackBarDuration with no tap.
      await tester.pump(const Duration(seconds: kSnackBarDuration + 1));
      await tester.pumpAndSettle();
      expect(_inviteSavedBar, findsNothing);
      // Auto-dismiss is the bar timing out, not the invite going away.
      expect(h.server.live, hasLength(1));
    },
  );

  // Guard: on desktop the QR waits behind "Show QR code" (#452). Once it was
  // on screen someone may have scanned it, so closing must keep the invite.
  testWidgets(
    'Forward invite: Show QR code then Close keeps the invite and shows '
    'Invite saved',
    (tester) async {
      final h = await _openInviteDialog(tester);

      await _tapInDialog(tester, 'Show QR code');
      expect(_inDialog(find.text('Show QR code')), findsNothing);

      await _closeAndSettle(tester);

      _expectKept(h);
    },
  );

  // Guard: on a phone the QR is the first thing the dialog shows, so it was
  // always on screen and may have been scanned — closing there never deletes
  // the invite (passes on today's code by design; pins the rule for the fix).
  testWidgets(
    'Forward invite: on a phone, Close keeps the invite (the QR was on '
    'screen) and shows Invite saved',
    (tester) async {
      final h = await _openInviteDialog(tester, size: _phone);
      // Compact layout: no "Show QR code" toggle, the QR is already shown.
      expect(_inDialog(find.text('Show QR code')), findsNothing);

      await _closeAndSettle(tester);

      _expectKept(h);
    },
  );

  // Guard: sharing through the system share sheet counts as using the
  // invite, even though no clipboard write and no "Link copied" bar happen.
  testWidgets(
    'Forward invite: Share link then Close keeps the invite and shows '
    'Invite saved',
    (tester) async {
      final shareCalls = _mockShareSheetSuccess(tester);
      final h = await _openInviteDialog(tester);

      await _tapInDialog(tester, 'Share link');
      expect(shareCalls, hasLength(1), reason: 'share sheet was opened');

      await _closeAndSettle(tester);

      _expectKept(h);
    },
  );
  // #605: on desktop the link is selectable text, so a person may copy it by
  // hand (select + Ctrl+C) instead of tapping Copy. That link must keep
  // working: closing the dialog keeps the invite.
  testWidgets(
    'Forward invite: on desktop, copying the link by hand then Close keeps '
    'the invite and shows Invite saved',
    (tester) async {
      _mockClipboard(tester);
      final h = await _openInviteDialog(tester);

      await _handCopyLink(tester);
      await _closeAndSettle(tester);

      _expectKept(h);
    },
  );
}
