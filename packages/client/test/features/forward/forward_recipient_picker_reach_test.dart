import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

Future<void> _scrollPickerUntilVisible(
  WidgetTester tester,
  Finder target,
) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byType(ForwardRecipientPicker),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Profile _voucher(String id, String name) => Profile(id: id, displayName: name);

ForwardReach _viaReach({
  required List<Profile> via,
  required int viaCount,
}) => ForwardReach(
  kind: ForwardReachKind.viaConnection,
  via: via,
  viaCount: viaCount,
);

ForwardCandidate _candidate({
  required String id,
  required String name,
  required ForwardReach reach,
  double score = 10,
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: score,
    rScore: 1,
    subjectExplicitlyTrustsViewer: true,
    sharesActiveContext: true,
  ),
  reach: reach,
);

ForwardCubit _pickerCubit(List<ForwardCandidate> candidates) {
  return ForwardCubit(
    beaconId: 'draft-1',
    debugSkipInitialLoad: true,
    embedded: true,
    effects: FakeUiEffectPort(),
  )..emit(
    ForwardState(
      beaconId: 'draft-1',
      beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
      candidates: candidates,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
}

Future<void> _pumpRuPhone(
  WidgetTester tester, {
  required ForwardCubit cubit,
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ForwardCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        ],
        child: const Scaffold(
          body: ForwardRecipientPicker(
            beaconId: 'draft-1',
            embedded: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reach kinds render three section headers in order', (
    tester,
  ) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'direct',
        name: 'Vadim',
        reach: const ForwardReach(kind: ForwardReachKind.direct),
      ),
      _candidate(
        id: 'via',
        name: 'Tanya',
        reach: _viaReach(
          via: [_voucher('U-v', 'Vadim')],
          viaCount: 1,
        ),
        score: 5,
      ),
      _candidate(
        id: 'shared',
        name: 'Ira',
        reach: const ForwardReach(
          kind: ForwardReachKind.sharedRequest,
          sharedRequest: (id: 'B1', title: 'Moving boxes'),
        ),
        score: 4,
      ),
      _candidate(
        id: 'wide',
        name: 'Kesi',
        reach: const ForwardReach(kind: ForwardReachKind.wider),
        score: 50,
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.text('OTHERS YOU CAN REACH'), findsNothing);
    expect(find.textContaining('Last seen'), findsNothing);

    final directY = tester
        .getTopLeft(find.byKey(ForwardRecipientPicker.directSectionKey))
        .dy;
    final throughY = tester
        .getTopLeft(find.byKey(ForwardRecipientPicker.throughSectionKey))
        .dy;
    expect(directY, lessThan(throughY));

    expect(find.text('ВАШИ СВЯЗИ'), findsOneWidget);
    expect(find.text('ЧЕРЕЗ ВАШИ СВЯЗИ'), findsOneWidget);
    expect(find.text('Kesi'), findsNothing);
    expect(
      find.byKey(ForwardRecipientPicker.widerSectionKey),
      findsNothing,
    );
    await _scrollPickerUntilVisible(
      tester,
      find.byKey(ForwardRecipientPicker.widerExpanderKey),
    );
    expect(
      find.byKey(ForwardRecipientPicker.widerExpanderKey),
      findsOneWidget,
    );
    expect(
      find.text('Ещё 1 человек в широкой сети'),
      findsOneWidget,
    );
    expect(find.text('Вы не знаете их лично.'), findsOneWidget);

    await tester.tap(find.byKey(ForwardRecipientPicker.widerExpanderKey));
    await tester.pumpAndSettle();

    await _scrollPickerUntilVisible(
      tester,
      find.byKey(ForwardRecipientPicker.widerSectionKey),
    );
    expect(find.text('ШИРОКАЯ СЕТЬ'), findsOneWidget);
    await _scrollPickerUntilVisible(tester, find.text('Kesi'));
    expect(find.text('Kesi'), findsOneWidget);
    expect(find.text('Дальняя связь'), findsOneWidget);
  });

  testWidgets('via row shows vouch copy and mini-avatars', (tester) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'via-two',
        name: 'Peer Two',
        reach: _viaReach(
          via: [_voucher('U-a', 'Alice'), _voucher('U-b', 'Bob')],
          viaCount: 2,
        ),
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.text('За них поручились Alice и Bob'), findsOneWidget);
    expect(find.byType(TenturaAvatarStack), findsOneWidget);
  });

  testWidgets('via_count 5 shows one name and others count', (tester) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'via-many',
        name: 'Peer Many',
        reach: _viaReach(
          via: [_voucher('U-a', 'Alice')],
          viaCount: 5,
        ),
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.text('За них поручился Alice и ещё 4'), findsOneWidget);
  });

  testWidgets('shared request row shows request title', (tester) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'shared',
        name: 'Ira',
        reach: const ForwardReach(
          kind: ForwardReachKind.sharedRequest,
          sharedRequest: (id: 'B1', title: 'Moving boxes'),
        ),
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.text('С вами в «Moving boxes»'), findsOneWidget);
  });

  testWidgets('wider row shows distant connection copy', (tester) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'wide',
        name: 'Kesi',
        reach: const ForwardReach(kind: ForwardReachKind.wider),
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.text('Дальняя связь'), findsOneWidget);
  });

  testWidgets('through section sorts by viaCount before score', (tester) async {
    final cubit = _pickerCubit([
      _candidate(
        id: 'low-via',
        name: 'Low Via High Score',
        reach: _viaReach(via: [_voucher('U-a', 'Alice')], viaCount: 1),
        score: 100,
      ),
      _candidate(
        id: 'high-via',
        name: 'High Via Low Score',
        reach: _viaReach(via: [_voucher('U-b', 'Bob')], viaCount: 3),
        score: 1,
      ),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    final highViaY = tester.getTopLeft(find.text('High Via Low Score')).dy;
    final lowViaY = tester.getTopLeft(find.text('Low Via High Score')).dy;
    expect(highViaY, lessThan(lowViaY));
  });

  testWidgets('already involved scope has no section headers', (tester) async {
    final cubit =
        ForwardCubit(
          beaconId: 'draft-1',
          debugSkipInitialLoad: true,
          embedded: true,
          effects: FakeUiEffectPort(),
        )..emit(
          ForwardState(
            beaconId: 'draft-1',
            beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
            activeFilter: ForwardFilter.alreadyInvolved,
            candidates: [
              _candidate(
                id: 'via',
                name: 'Tanya',
                reach: _viaReach(via: [_voucher('U-v', 'Vadim')], viaCount: 1),
              ).copyWith(involvement: CandidateInvolvement.forwardedByMe),
            ],
            candidatesLoad: const ForwardCandidatesReady(),
          ),
        );
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit: cubit);

    expect(find.byKey(ForwardRecipientPicker.directSectionKey), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.throughSectionKey), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.widerSectionKey), findsNothing);
    expect(find.text('Tanya'), findsOneWidget);
  });
}
