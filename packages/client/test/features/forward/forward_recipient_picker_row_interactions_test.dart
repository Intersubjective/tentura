import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

import '../../support/phone_surface.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeContextRepo implements ForwardCandidateContextRepositoryPort {
  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) async => const CandidateConnectionContext(
    status: CandidateConnectionContextStatus.unavailable,
    nodes: [],
  );
}

ForwardCandidate _candidate({
  required String id,
  required String name,
  ForwardReach? reach,
  DateTime? joinedAt,
  int myVote = 0,
  Set<String> capabilitySlugs = const {},
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: 10,
    rScore: 1,
    myVote: myVote,
    joinedAt: joinedAt,
    subjectExplicitlyTrustsViewer: true,
    sharesActiveContext: true,
  ),
  reach: reach ?? const ForwardReach(kind: ForwardReachKind.wider),
  topCapabilities: capabilitySlugs.toList(),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required ForwardCandidate candidate,
  ForwardRecipientRowHost host = ForwardRecipientRowHost.pickerStandard,
  VoidCallback? onToggle,
  VoidCallback? onOpenDetails,
  Set<String> requiredCapabilitySlugs = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(),
        child: Scaffold(
          body: ForwardRecipientRow(
            host: host,
            candidate: candidate,
            isSelected: false,
            onToggle: onToggle,
            onOpenDetails: onOpenDetails,
            requiredCapabilitySlugs: requiredCapabilitySlugs,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GetIt.I.registerSingleton<LoadForwardCandidateContextCase>(
      LoadForwardCandidateContextCase(
        _FakeContextRepo(),
        env: const Env(),
        logger: Logger('ForwardRecipientPickerRowInteractionsTest'),
      ),
    );
  });

  tearDownAll(GetIt.I.reset);

  testWidgets('pickerStandard: name tap toggles without opening details', (
    tester,
  ) async {
    var toggles = 0;
    var opens = 0;
    await _pumpRow(
      tester,
      candidate: _candidate(id: 'u1', name: 'Alex'),
      onToggle: () => toggles++,
      onOpenDetails: () => opens++,
    );

    await tester.tap(find.text('Alex'));
    await tester.pump();

    expect(toggles, 1);
    expect(opens, 0);
  });

  testWidgets('pickerStandard: avatar tap opens details without toggling', (
    tester,
  ) async {
    var toggles = 0;
    var opens = 0;
    await _pumpRow(
      tester,
      candidate: _candidate(id: 'u1', name: 'Alex'),
      onToggle: () => toggles++,
      onOpenDetails: () => opens++,
    );

    await tester.tap(find.byType(SelfAwareAvatar));
    await tester.pump();

    expect(opens, 1);
    expect(toggles, 0);
  });

  testWidgets('pickerStandard: info button opens details', (tester) async {
    var opens = 0;
    await _pumpRow(
      tester,
      candidate: _candidate(id: 'u1', name: 'Alex'),
      onOpenDetails: () => opens++,
    );

    await tester.tap(
      find.byKey(TestIds.key(TestIds.forwardRecipientDetails('u1'))),
    );
    await tester.pump();

    expect(opens, 1);
  });

  testWidgets('pickerStandard: mouse hover on name shows reason card', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      candidate: _candidate(
        id: 'u1',
        name: 'Alex',
        reach: const ForwardReach(kind: ForwardReachKind.wider),
      ),
    );

    final center = tester.getCenter(find.text('Alex'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Distant connection'), findsWidgets);
    expect(
      find.byKey(const Key('forward.picker.hover.card.u1')),
      findsOneWidget,
    );
  });

  testWidgets('pickerStandard: touch pointer does not show hover card', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      candidate: _candidate(id: 'u1', name: 'Alex'),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.moveTo(tester.getCenter(find.text('Alex')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const Key('forward.picker.hover.card.u1')),
      findsNothing,
    );
  });

  testWidgets('pickerStandard: secondary tap on row opens details', (
    tester,
  ) async {
    var opens = 0;
    await _pumpRow(
      tester,
      candidate: _candidate(id: 'u1', name: 'Alex'),
      onOpenDetails: () => opens++,
    );

    final center = tester.getCenter(find.text('Alex'));
    await tester.sendEventToBinding(
      PointerDownEvent(
        position: center,
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.pump();

    expect(opens, 1);
  });

  testWidgets('pickerBand: row tap still opens details only', (tester) async {
    var toggles = 0;
    var opens = 0;
    await _pumpRow(
      tester,
      host: ForwardRecipientRowHost.pickerBand,
      candidate: _candidate(id: 'u1', name: 'Alex'),
      onToggle: () => toggles++,
      onOpenDetails: () => opens++,
    );

    await tester.tap(find.byKey(TestIds.key(TestIds.forwardRecipient('u1'))));
    await tester.pump();

    expect(opens, 1);
    expect(toggles, 0);
  });

  testWidgets('375x667 RU: details tooltip on info button', (tester) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: BlocProvider<ProfileCubit>.value(
          value: _MockProfileCubit(),
          child: Scaffold(
            body: ForwardRecipientRow(
              host: ForwardRecipientRowHost.pickerStandard,
              candidate: _candidate(id: 'u1', name: 'Алекс'),
              isSelected: false,
              onToggle: () {},
              onOpenDetails: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Подробнее'), findsOneWidget);
  });
}
