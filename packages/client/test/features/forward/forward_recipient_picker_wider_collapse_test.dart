import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
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

ForwardCandidate _wider(String id, String name) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: 1,
    rScore: 1,
    subjectExplicitlyTrustsViewer: true,
    sharesActiveContext: true,
  ),
  reach: const ForwardReach(kind: ForwardReachKind.wider),
);

ForwardCandidate _direct(String id, String name) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: name,
    score: 10,
    rScore: 1,
    myVote: 1,
    subjectExplicitlyTrustsViewer: true,
    sharesActiveContext: true,
  ),
  reach: const ForwardReach(kind: ForwardReachKind.direct),
);

ForwardCubit _cubit(
  List<ForwardCandidate> candidates, {
  Set<String>? selected,
}) {
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
          candidates: candidates,
          selectedIds: selected ?? const {},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
  return cubit;
}

Finder _embeddedRecipientSearchField() => find.descendant(
  of: find.byType(ForwardRecipientPicker),
  matching: find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.isCollapsed ?? false),
  ),
);

Future<void> _pumpEnPhone(WidgetTester tester, ForwardCubit cubit) async {
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

Future<void> _pumpRuPhone(WidgetTester tester, ForwardCubit cubit) async {
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
  testWidgets('1 direct + 9 wider: expander hides wider until tapped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final wider = List.generate(
      9,
      (i) => _wider('w$i', 'Wide $i'),
    );
    final cubit = _cubit([_direct('d1', 'Direct'), ...wider]);
    addTearDown(cubit.close);
    await _pumpEnPhone(tester, cubit);

    expect(find.text('Direct'), findsOneWidget);
    for (final c in wider) {
      expect(find.text(c.profile.displayName), findsNothing);
    }
    await _scrollPickerUntilVisible(
      tester,
      find.byKey(ForwardRecipientPicker.widerExpanderKey),
    );
    expect(
      find.text('9 more people in your wider network'),
      findsOneWidget,
    );
    expect(find.text("You don't know them directly."), findsOneWidget);

    await tester.tap(find.byKey(ForwardRecipientPicker.widerExpanderKey));
    await tester.pumpAndSettle();

    expect(find.text('9 more people in your wider network'), findsNothing);
    expect(find.text('WIDER NETWORK'), findsOneWidget);
    for (final c in wider) {
      await _scrollPickerUntilVisible(
        tester,
        find.text(c.profile.displayName),
      );
      expect(find.text(c.profile.displayName), findsOneWidget);
    }
  });

  testWidgets('wider only: all rows, no expander', (tester) async {
    await usePhoneSurface(tester);
    final cubit = _cubit([
      _wider('w1', 'Only One'),
      _wider('w2', 'Only Two'),
    ]);
    addTearDown(cubit.close);
    await _pumpEnPhone(tester, cubit);

    expect(find.text('Only One'), findsOneWidget);
    expect(find.text('Only Two'), findsOneWidget);
    expect(find.byKey(ForwardRecipientPicker.widerExpanderKey), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.widerSectionKey), findsNothing);
  });

  testWidgets('search match shows wider row without expander', (tester) async {
    await usePhoneSurface(tester);
    final cubit = _cubit([
      _direct('d1', 'Direct'),
      _wider('w1', 'Hidden Wide'),
      _wider('w2', 'Find Me'),
    ]);
    addTearDown(cubit.close);
    await _pumpEnPhone(tester, cubit);

    await tester.enterText(_embeddedRecipientSearchField(), 'Find');
    await tester.pumpAndSettle();

    expect(find.text('Find Me'), findsOneWidget);
    expect(find.text('Hidden Wide'), findsNothing);
    expect(find.byKey(ForwardRecipientPicker.widerExpanderKey), findsNothing);
  });

  testWidgets('selected wider stays visible above expander when collapsed', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final cubit = _cubit(
      [
        _direct('d1', 'Direct'),
        _wider('w1', 'Pinned'),
        _wider('w2', 'Hidden A'),
        _wider('w3', 'Hidden B'),
      ],
      selected: {'w1'},
    );
    addTearDown(cubit.close);
    await _pumpEnPhone(tester, cubit);

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Hidden A'), findsNothing);
    expect(find.text('Hidden B'), findsNothing);
    await _scrollPickerUntilVisible(
      tester,
      find.byKey(ForwardRecipientPicker.widerExpanderKey),
    );
    expect(
      find.text('2 more people in your wider network'),
      findsOneWidget,
    );
  });

  testWidgets('375x667 RU: expander copy and expand', (tester) async {
    final cubit = _cubit([
      _direct('d1', 'Вадим'),
      _wider('w1', 'Kesi'),
    ]);
    addTearDown(cubit.close);
    await _pumpRuPhone(tester, cubit);

    await _scrollPickerUntilVisible(
      tester,
      find.byKey(ForwardRecipientPicker.widerExpanderKey),
    );
    expect(find.text('Ещё 1 человек в широкой сети'), findsOneWidget);
    expect(find.text('Вы не знаете их лично.'), findsOneWidget);
    expect(find.text('Kesi'), findsNothing);

    await tester.tap(find.byKey(ForwardRecipientPicker.widerExpanderKey));
    await tester.pumpAndSettle();

    expect(find.text('ШИРОКАЯ СЕТЬ'), findsOneWidget);
    expect(find.text('Kesi'), findsOneWidget);
  });
}
