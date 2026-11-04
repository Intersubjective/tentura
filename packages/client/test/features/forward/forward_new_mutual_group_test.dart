import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final _fixedNow = DateTime.utc(2026, 11, 4, 12);

ForwardCubit _cubit({
  required List<ForwardCandidate> candidates,
  ForwardFilter filter = ForwardFilter.unseen,
}) {
  return ForwardCubit(
    beaconId: 'draft-1',
    debugSkipInitialLoad: true,
    embedded: true,
    effects: FakeUiEffectPort(),
    clock: () => _fixedNow,
  )..emit(
    ForwardState(
      beaconId: 'draft-1',
      beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
      candidates: candidates,
      activeFilter: filter,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
}

ForwardCandidate _candidate({
  required String id,
  required String name,
  DateTime? mutualSince,
  double score = 10,
  int myVote = 0,
  CandidateInvolvement involvement = CandidateInvolvement.unseen,
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: score,
    rScore: 1,
    myVote: myVote,
    mutualSince: mutualSince,
  ),
  mutualSince: mutualSince,
  involvement: involvement,
);

Future<void> _pumpEmbedded(
  WidgetTester tester, {
  required ForwardCubit cubit,
  Locale locale = const Locale('en'),
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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

final _embeddedSearchField = find.descendant(
  of: find.byType(ForwardRecipientPicker),
  matching: find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.isCollapsed ?? false),
  ),
);

void main() {
  testWidgets(
    '«New» section orders newest mutual first and dedupes from below',
    (
      tester,
    ) async {
      final older = _fixedNow.subtract(const Duration(days: 2));
      final newer = _fixedNow.subtract(const Duration(hours: 6));
      final cubit = _cubit(
        candidates: [
          _candidate(
            id: 'old',
            name: 'Older Mutual',
            mutualSince: older,
            myVote: 1,
          ),
          _candidate(
            id: 'new',
            name: 'Newer Mutual',
            mutualSince: newer,
            myVote: 1,
          ),
          _candidate(
            id: 'friend',
            name: 'Old Friend',
            myVote: 1,
            score: 50,
          ),
        ],
      );
      addTearDown(cubit.close);
      await _pumpEmbedded(tester, cubit: cubit);

      expect(find.byKey(ForwardRecipientPicker.newSectionKey), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);

      final newY = tester.getTopLeft(find.text('Newer Mutual')).dy;
      final oldMutualY = tester.getTopLeft(find.text('Older Mutual')).dy;
      final directHeaderY = tester
          .getTopLeft(find.byKey(ForwardRecipientPicker.directSectionKey))
          .dy;
      final friendY = tester.getTopLeft(find.text('Old Friend')).dy;

      expect(newY, lessThan(oldMutualY));
      expect(oldMutualY, lessThan(directHeaderY));
      expect(directHeaderY, lessThan(friendY));
      expect(find.text('Older Mutual'), findsOneWidget);
      expect(find.text('Old Friend'), findsOneWidget);
    },
  );

  testWidgets('empty «New» section stays hidden', (tester) async {
    final cubit = _cubit(
      candidates: [
        _candidate(id: 'u1', name: 'Only Friend', myVote: 1),
      ],
    );
    addTearDown(cubit.close);
    await _pumpEmbedded(tester, cubit: cubit);

    expect(find.byKey(ForwardRecipientPicker.newSectionKey), findsNothing);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('embedded search flattens groups and filters across them', (
    tester,
  ) async {
    final cubit = _cubit(
      candidates: [
        _candidate(
          id: 'new',
          name: 'Новый контакт',
          mutualSince: _fixedNow.subtract(const Duration(days: 1)),
          myVote: 1,
        ),
        _candidate(id: 'other', name: 'Дальний знакомый', score: 40),
      ],
    );
    addTearDown(cubit.close);
    await _pumpEmbedded(tester, cubit: cubit, locale: const Locale('ru'));

    expect(_embeddedSearchField, findsOneWidget);
    expect(find.text('НОВЫЕ'), findsOneWidget);

    await tester.enterText(_embeddedSearchField, 'даль');
    await tester.pumpAndSettle();

    expect(find.text('НОВЫЕ'), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.newSectionKey), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.directSectionKey), findsNothing);
    expect(find.text('Дальний знакомый'), findsOneWidget);
    expect(find.text('Новый контакт'), findsNothing);
  });

  testWidgets('375×667 RU: hint and long names render without overflow', (
    tester,
  ) async {
    final cubit = _cubit(
      candidates: [
        _candidate(
          id: 'long',
          name: 'Александр Константинопольский длинное имя',
          mutualSince: _fixedNow.subtract(const Duration(days: 1)),
          myVote: 1,
        ),
      ],
    );
    addTearDown(cubit.close);
    await _pumpEmbedded(tester, cubit: cubit, locale: const Locale('ru'));

    expect(find.text('НОВЫЕ'), findsOneWidget);
    expect(
      find.text('Взаимное доверие за последнюю неделю'),
      findsOneWidget,
    );
    expect(
      find.text('Александр Константинопольский длинное имя'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Select all» in «New» selects eligible people only', (
    tester,
  ) async {
    final cubit = _cubit(
      candidates: [
        _candidate(
          id: 'n1',
          name: 'One',
          mutualSince: _fixedNow.subtract(const Duration(days: 1)),
          myVote: 1,
        ),
        _candidate(
          id: 'n2',
          name: 'Two',
          mutualSince: _fixedNow.subtract(const Duration(days: 2)),
          myVote: 1,
        ),
      ],
    );
    addTearDown(cubit.close);
    await _pumpEmbedded(tester, cubit: cubit);

    await tester.tap(
      find.byKey(const Key('ForwardRecipientPicker.newSelectAll')),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.selectedIds, {'n1', 'n2'});
    expect(
      find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('n1'))),
      findsOneWidget,
    );
  });
}
