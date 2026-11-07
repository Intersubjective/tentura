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
import 'package:tentura/features/forward/ui/widget/forward_scope_links.dart';
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

ForwardCubit _cubit({required List<ForwardCandidate> candidates}) {
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
      activeFilter: ForwardFilter.unseen,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
}

ForwardCandidate _newMutual({
  required String id,
  required String name,
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: 10,
    rScore: 1,
    myVote: 1,
    mutualSince: _fixedNow.subtract(const Duration(days: 1)),
  ),
  mutualSince: _fixedNow.subtract(const Duration(days: 1)),
  involvement: CandidateInvolvement.unseen,
);

void main() {
  testWidgets(
    '375×667 RU embedded: centre tap on «Выбрать все» selects New rows',
    (tester) async {
      final cubit = _cubit(
        candidates: [
          _newMutual(id: 'n1', name: 'Анна Петрова'),
          _newMutual(id: 'n2', name: 'Борис Иванов'),
          _newMutual(id: 'n3', name: 'Виктория Смирнова'),
          _newMutual(id: 'n4', name: 'Григорий Николаев'),
        ],
      );
      addTearDown(cubit.close);

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

      final selectAll = find.byKey(
        const Key('ForwardRecipientPicker.newSelectAll'),
      );
      final scopeTabs = find.byType(ForwardScopeLinks);
      expect(selectAll, findsOneWidget);
      expect(scopeTabs, findsOneWidget);

      final selectAllBottom = tester.getBottomLeft(selectAll).dy;
      final tabsBottom = tester.getBottomLeft(scopeTabs).dy;
      expect(
        selectAllBottom,
        lessThan(tabsBottom),
        reason: '«Выбрать все» must sit wholly above the pinned scope tabs',
      );

      await tester.tap(selectAll);
      await tester.pumpAndSettle();

      expect(cubit.state.activeFilter, ForwardFilter.unseen);
      expect(cubit.state.selectedIds, {'n1', 'n2', 'n3', 'n4'});
      expect(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('n1'))),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '375×667 RU embedded: first New row is visible below the scope tabs',
    (tester) async {
      final cubit = _cubit(
        candidates: [
          _newMutual(
            id: 'long',
            name: 'Александр Константинопольский длинное имя',
          ),
        ],
      );
      addTearDown(cubit.close);

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

      final rowName = find.text('Александр Константинопольский длинное имя');
      final tabsBottom = tester
          .getBottomLeft(find.byType(ForwardScopeLinks))
          .dy;
      final rowTop = tester.getTopLeft(rowName).dy;
      final viewportBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;

      expect(rowTop, greaterThan(tabsBottom));
      expect(rowTop, lessThan(viewportBottom));
      expect(
        find.text('Взаимное доверие за последнюю неделю'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
