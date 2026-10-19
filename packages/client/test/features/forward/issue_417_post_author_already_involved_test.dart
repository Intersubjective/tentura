import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

// #417: on a Post, the forward picker's "Already involved" tab said 0 and
// listed nobody, although the post's author is involved by definition.

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

const _author = ForwardCandidate(
  profile: Profile(
    id: 'author',
    displayName: 'Tab QA',
    rScore: 1,
    score: 70,
  ),
  involvement: CandidateInvolvement.author,
);

const _unseen = ForwardCandidate(
  profile: Profile(
    id: 'orphan',
    displayName: 'Orphan QA',
    rScore: 1,
    score: 40,
  ),
);

ForwardState _postState({
  ForwardFilter filter = ForwardFilter.alreadyInvolved,
}) => ForwardState(
  beaconId: 'P1',
  beacon: Beacon.empty.copyWith(
    id: 'P1',
    title: 'A post',
    kind: BeaconKind.post,
  ),
  candidates: const [_unseen, _author],
  activeFilter: filter,
  candidatesLoad: const ForwardCandidatesReady(),
);

void main() {
  group('ForwardState on a Post (#417)', () {
    test('Already involved counts and lists the post author', () {
      final state = _postState();

      expect(state.scopeCounts.involved, 1);
      expect(
        state.visibleRecipients.map((c) => c.id).toList(),
        ['author'],
      );
      // Not a recipient: the author stays out of "Not yet seen" and cannot
      // be picked.
      expect(state.scopeCounts.unseen, 1);
      expect(state.visibleRecipients.single.canForwardTo, isFalse);
      expect(
        _postState(
          filter: ForwardFilter.unseen,
        ).visibleRecipients.map((c) => c.id).toList(),
        ['orphan'],
      );
    });

    test('the post author is listed once when also a lineage row', () {
      final state = _postState().copyWith(
        lineageSuggestions: const [
          ForwardCandidate(
            profile: Profile(
              id: 'author',
              displayName: 'Tab QA',
              rScore: 1,
              score: 70,
            ),
            involvement: CandidateInvolvement.author,
          ),
        ],
      );

      expect(state.scopeCounts.involved, 1);
      expect(
        state.visibleRecipients.map((c) => c.id).toList(),
        ['author'],
      );
    });
  });

  group('ForwardRecipientPicker on a Post (#417)', () {
    setUp(() {
      GetIt.I
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
        ..registerSingleton<InvitationRepository>(
          _FakeInvitationRepository(),
        );
    });

    tearDown(() async {
      await GetIt.I.unregister<InvitationRepository>();
      await GetIt.I.unregister<UiEffectPort>();
    });

    testWidgets('Already involved tab shows the author, not selectable', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final cubit = ForwardCubit(
        beaconId: 'P1',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(_postState());

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const Scaffold(
              body: ForwardRecipientPicker(beaconId: 'P1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scope tab reads "Already involved  1" (it read "Already involved  0").
      expect(
        find.text('Already involved\u20021', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('There is nothing here yet'), findsNothing);

      final authorBox = find.byKey(
        TestIds.key(TestIds.forwardRecipientCheckbox('author')),
      );
      expect(authorBox, findsOneWidget);
      expect(
        tester.getSemantics(authorBox),
        isSemantics(
          label: 'Tab QA',
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      // The unseen recipient belongs to the other tab.
      expect(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('orphan'))),
        findsNothing,
      );
      handle.dispose();
    });
  });
}
