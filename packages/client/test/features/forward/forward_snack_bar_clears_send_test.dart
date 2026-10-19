import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../../ui/snack_bar_clearance_support.dart';

// #406: on Forward, the «Invite saved» notice and error bars were drawn
// across the «Forward to N» button, which could not be tapped until the bar
// was closed.

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
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
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

const _errorText = 'Image is not attached to this request';

final _sendButton = find.byKey(TestIds.key(TestIds.forwardSubmit));

void _registerServices() {
  GetIt.I
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<Logger>(Logger('test'));
  addTearDown(GetIt.I.reset);
}

ForwardCubit _cubitWithOneSelected() {
  final cubit =
      ForwardCubit(
        beaconId: 'b1',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      )..emit(
        ForwardState(
          beaconId: 'b1',
          beacon: Beacon.empty.copyWith(
            id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
            title: 'Test beacon',
            context: 'General',
            viewerCanForward: true,
            startAt: DateTime.utc(2025, 5, 12),
            endAt: DateTime.utc(2025, 5, 19),
          ),
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
          selectedIds: const {'u1'},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
  return cubit;
}

Future<void> _pumpForwardPage(
  WidgetTester tester, {
  required ForwardCubit cubit,
  required Size size,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

/// Lets the bar finish its entrance animation without waiting out its
/// auto-dismiss timer.
Future<void> _showBar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

const _noteText = 'Could you take a look at this?';

const _plainNotice = 'Saved';

final _coverKey = GlobalKey(debugLabel: 'cover');

final _homeKey = GlobalKey(debugLabel: 'home');

/// Expands the shared note the way the app does on its own: a lineage
/// suggestion arrives together with a prefilled note, so the composer grows
/// (note field + suggested-note helper) above «Forward to 1».
Future<void> _expandNote(WidgetTester tester, ForwardCubit cubit) async {
  cubit.emit(
    cubit.state.copyWith(
      note: _noteText,
      lineageSuggestions: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u2',
            displayName: 'Lena',
            rScore: 1,
            score: 5,
          ),
          lineageReasonCode: 'prior_forward',
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// Shows the «Invite saved» notice from inside the picker, as the invite
/// flow does, and checks it clears «Forward to 1».
Future<void> _expectPickerNoticeClearsSend(WidgetTester tester) async {
  final pickerContext = tester.element(find.byType(ForwardRecipientPicker));
  final message = L10n.of(pickerContext)!.forwardInviteCreatedHint;
  showSnackBar(pickerContext, text: message);
  await _showBar(tester);
  expectSnackBarClearsButton(tester, message: message, button: _sendButton);
}

Future<void> _removeBars(WidgetTester tester) async {
  snackbarKey.currentState!.removeCurrentSnackBar();
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
}

Widget _forwardRoute(ForwardCubit cubit) => MultiBlocProvider(
  providers: [
    BlocProvider<ForwardCubit>.value(value: cubit),
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
  ],
  child: const ForwardBeaconPage(beaconId: 'b1'),
);

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets(
      'Forward ($label): the Invite saved notice sits above Forward to 1',
      (tester) async {
        _registerServices();
        final cubit = _cubitWithOneSelected();
        addTearDown(cubit.close);
        await _pumpForwardPage(tester, cubit: cubit, size: size);

        // Precondition: the primary action is the enabled «Forward to 1».
        expect(
          find.descendant(of: _sendButton, matching: find.text('Forward to 1')),
          findsOneWidget,
        );

        // Shown exactly as the invite flow shows it: from inside the picker.
        final pickerContext = tester.element(
          find.byType(ForwardRecipientPicker),
        );
        final message = L10n.of(pickerContext)!.forwardInviteCreatedHint;
        showSnackBar(
          pickerContext,
          text: message,
          action: SnackBarAction(
            label: L10n.of(pickerContext)!.forwardViewInvitations,
            onPressed: () {},
          ),
        );
        await _showBar(tester);

        expectSnackBarClearsButton(
          tester,
          message: message,
          button: _sendButton,
        );
      },
    );

    testWidgets(
      'Forward ($label): an error bar raised above the picker sits above '
      'Forward to 1',
      (tester) async {
        _registerServices();
        final cubit = _cubitWithOneSelected();
        addTearDown(cubit.close);
        await _pumpForwardPage(tester, cubit: cubit, size: size);

        // Errors come from the screen-level effect handler, whose context is
        // above the picker (and above any messenger the picker might own).
        showSnackBar(
          tester.element(find.byType(ForwardBeaconPage)),
          text: _errorText,
          isError: true,
        );
        await _showBar(tester);

        expectSnackBarClearsButton(
          tester,
          message: _errorText,
          button: _sendButton,
        );
      },
    );
  }
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets(
      'Forward ($label): with the note expanded the bar still sits above '
      'Forward to 1',
      (tester) async {
        _registerServices();
        final cubit = _cubitWithOneSelected();
        addTearDown(cubit.close);
        await _pumpForwardPage(tester, cubit: cubit, size: size);

        final collapsed = tester.getSize(find.byType(ForwardBottomComposer));
        await _expandNote(tester, cubit);

        // Precondition: the composer really is taller now (note field and
        // the suggested-note helper above the button), so a fixed offset
        // sized for the collapsed composer cannot pass.
        expect(find.byKey(TestIds.key(TestIds.forwardNote)), findsOneWidget);
        expect(
          find.text(
            L10n.of(
              tester.element(find.byType(ForwardRecipientPicker)),
            )!.beaconLineageSuggestedNoteHelper,
          ),
          findsOneWidget,
        );
        final expanded = tester.getSize(find.byType(ForwardBottomComposer));
        expect(expanded.height, greaterThan(collapsed.height + 64));
        expect(
          find.descendant(of: _sendButton, matching: find.text('Forward to 1')),
          findsOneWidget,
        );

        await _expectPickerNoticeClearsSend(tester);

        // An error raised above the picker clears the taller composer too.
        showSnackBar(
          tester.element(find.byType(ForwardBeaconPage)),
          text: _errorText,
          isError: true,
        );
        await _showBar(tester);
        expectSnackBarClearsButton(
          tester,
          message: _errorText,
          button: _sendButton,
        );
      },
    );
  }

  testWidgets(
    'Forward: a bar on a route pushed over Forward sits at the default '
    'placement (the covered picker lends it no clearance)',
    (tester) async {
      _registerServices();
      final cubit = _cubitWithOneSelected();
      addTearDown(cubit.close);
      await _pumpForwardPage(tester, cubit: cubit, size: const Size(390, 844));

      // Clearance is in effect while Forward is on top.
      await _expectPickerNoticeClearsSend(tester);
      await _removeBars(tester);

      Navigator.of(tester.element(find.byType(ForwardBeaconPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(key: _coverKey, body: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      // Precondition: the picker is still mounted, just offstage.
      expect(find.byType(ForwardRecipientPicker), findsNothing);
      expect(
        find.byType(ForwardRecipientPicker, skipOffstage: false),
        findsOneWidget,
      );

      showSnackBar(tester.element(find.byKey(_coverKey)), text: _plainNotice);
      await _showBar(tester);
      expectSnackBarAtDefaultPlacement(tester, message: _plainNotice);
    },
  );

  testWidgets(
    'Forward: after Forward is popped a bar elsewhere sits at the default '
    'placement (no clearance left behind)',
    (tester) async {
      _registerServices();
      final cubit = _cubitWithOneSelected();
      addTearDown(cubit.close);
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: snackbarKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(key: _homeKey, body: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byKey(_homeKey))).push(
        MaterialPageRoute<void>(builder: (_) => _forwardRoute(cubit)),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _sendButton, matching: find.text('Forward to 1')),
        findsOneWidget,
      );

      // Clearance is in effect while Forward is shown.
      await _expectPickerNoticeClearsSend(tester);
      await _removeBars(tester);

      Navigator.of(tester.element(find.byType(ForwardBeaconPage))).pop();
      await tester.pumpAndSettle();

      // Precondition: the picker is gone for good.
      expect(
        find.byType(ForwardRecipientPicker, skipOffstage: false),
        findsNothing,
      );

      showSnackBar(tester.element(find.byKey(_homeKey)), text: _plainNotice);
      await _showBar(tester);
      expectSnackBarAtDefaultPlacement(tester, message: _plainNotice);
    },
  );
}
