// The graph composer sheet offers the same tag chip row as the forward
// picker: a tag adds its people to the recipients (circle untouched), a second
// tap takes back only the people it added alone.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_composer_sheet.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_tag_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

/// Same keys as the forward picker's chip row.
ValueKey<String> _tagChip(String tagId) => ValueKey('forward-tag-chip-$tagId');

ValueKey<String> _autoChip(int kind) => ValueKey('forward-tag-chip-auto-$kind');

String _arbText(String key) =>
    (jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>)[key]!
        as String;

Key _recipientChip(String id) => Key('constellation.composer.chip.$id');

/// Three people close to the draft, two far away.
const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
  'Ud': Offset(100, 0),
  'Ue': Offset(200, 0),
};

final _profiles = [
  for (final id in _positions.keys)
    Profile(
      id: id,
      displayName: 'Person $id',
      sharesActiveContext: true,
      score: 1,
      rScore: 1,
    ),
];

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

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  @override
  Future<List<PersonTag>> personTags() async => const [
    PersonTag(id: 'Tn', name: 'Neighbours', glyph: 'N', color: 0, ord: 0),
    PersonTag(id: 'Tc', name: 'Climbers', glyph: 'C', color: 1, ord: 1),
  ];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [
    PersonTagMembers(tagId: 'Tn', personIds: ['Ua', 'Ud']),
    PersonTagMembers(tagId: 'Tc', personIds: ['Ud', 'Ue']),
  ];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [
    PersonAutoTag(kind: 3, count: 1, showInFilters: true),
    PersonAutoTag(kind: 5, count: 1, showInFilters: true),
  ];

  @override
  Future<List<String>> personAutoTagMembers(int kind) async => switch (kind) {
    3 => ['Ua'],
    5 => ['Ue'],
    _ => [],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late FakeUiEffectPort effects;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
    effects = FakeUiEffectPort();
    forwards = [];
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      _FakePeopleTagsRepository(),
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await peopleTags.load();
    GetIt.I
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<PeopleTagsCase>(peopleTags);
    composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
  });

  tearDown(() async {
    await composer.close();
    for (final f in forwards) {
      await f.close();
    }
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  /// Starts a Post composer at the origin (start radius 33: Ua, Ub, Uc are
  /// selected) and creates the server draft with its list candidates.
  Future<ForwardCubit> startPost(WidgetTester tester) async {
    composer.start(BeaconKind.post, Offset.zero);
    await tester.runAsync(() async {
      await composer.contentChanged();
      await Future<void>.delayed(Duration.zero);
    });
    final forward = composer.forwardCubit!;
    forward.emit(
      forward.state.copyWith(
        candidates: [for (final p in _profiles) ForwardCandidate(profile: p)],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );
    return forward;
  }

  Future<void> pumpSheet(WidgetTester tester, {required Size size}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ConstellationComposerSheet(
                composer: composer,
                onOpenFullForm: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the chip's button semantics are marked selected, as the
  /// forward picker marks an active tag.
  bool isActive(WidgetTester tester, Key chip) {
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(chip),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.button == true,
            ),
          )
          .first,
    );
    return semantics.properties.selected ?? false;
  }

  const narrow = Size(420, 900);
  const wide = Size(1200, 900);

  for (final (name, size) in [('narrow sheet', narrow), ('wide panel', wide)]) {
    group('tag chips in the composer $name', () {
      testWidgets('host the forward picker chip row: own tags, then the '
          'Helped me and Worked together chips with their labels', (
        tester,
      ) async {
        await startPost(tester);
        await pumpSheet(tester, size: size);

        expect(find.byType(ForwardTagPicker), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ConstellationComposerSheet),
            matching: find.byType(ForwardTagPicker),
          ),
          findsOneWidget,
        );
        for (final k in [
          _tagChip('Tn'),
          _tagChip('Tc'),
          _autoChip(3),
          _autoChip(5),
        ]) {
          expect(find.byKey(k), findsOneWidget);
        }
        expect(
          find.descendant(
            of: find.byKey(_tagChip('Tn')),
            matching: find.text('Neighbours'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_autoChip(3)),
            matching: find.text(_arbText('peopleTagsAutoHelpedMe')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_autoChip(5)),
            matching: find.text(_arbText('peopleTagsAutoWorkedTogether')),
          ),
          findsOneWidget,
        );
        Offset at(Key k) => tester.getTopLeft(find.byKey(k));
        bool before(Key a, Key b) =>
            at(a).dy < at(b).dy ||
            (at(a).dy == at(b).dy && at(a).dx < at(b).dx);
        final order = [
          _tagChip('Tn'),
          _tagChip('Tc'),
          _autoChip(3),
          _autoChip(5),
        ];
        for (var i = 0; i + 1 < order.length; i++) {
          expect(before(order[i], order[i + 1]), isTrue, reason: '$i');
        }
      });

      testWidgets('mark a tag chip active only while its tag is picked', (
        tester,
      ) async {
        await startPost(tester);
        await pumpSheet(tester, size: size);
        expect(isActive(tester, _tagChip('Tn')), isFalse);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        expect(isActive(tester, _tagChip('Tn')), isTrue);
        expect(isActive(tester, _tagChip('Tc')), isFalse);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        expect(isActive(tester, _tagChip('Tn')), isFalse);
      });

      testWidgets('tapping a tag adds its people outside the circle as '
          'recipient chips and to the forward draft', (tester) async {
        final forward = await startPost(tester);
        await pumpSheet(tester, size: size);
        final radius = composer.selection.radius;

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();

        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ud'});
        expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ud'});
        expect(find.byKey(_recipientChip('Ud')), findsOneWidget);
        expect(composer.selection.radius, radius);
      });

      testWidgets('a picked tag shows the forward note and an outside-the-tag '
          'hint without the tag members', (tester) async {
        await startPost(tester);
        await pumpSheet(tester, size: size);
        const hint = ValueKey('forward-tag-outside-hint');
        expect(find.byKey(hint), findsNothing);
        expect(find.byKey(const ValueKey('forward-tag-note')), findsOneWidget);
        expect(find.text(_arbText('peopleTagsForwardNote')), findsOneWidget);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();

        expect(find.byKey(hint), findsOneWidget);
        expect(find.text(_arbText('peopleTagsForwardNote')), findsOneWidget);
        final rows = [
          for (final id in _positions.keys)
            if (find
                .byKey(ValueKey('forward-tag-outside-$id'))
                .evaluate()
                .isNotEmpty)
              id,
        ];
        // Tn holds Ua and Ud; only the other eligible people are offered.
        expect(rows.toSet(), {'Ub', 'Uc', 'Ue'});
        expect(rows.length, lessThanOrEqualTo(3));
      });

      testWidgets('tapping the tag again removes only the people it added, '
          'not those inside the circle', (tester) async {
        final forward = await startPost(tester);
        await pumpSheet(tester, size: size);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();

        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
        expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc'});
        expect(find.byKey(_recipientChip('Ud')), findsNothing);
        expect(find.byKey(_recipientChip('Ua')), findsOneWidget);
      });

      testWidgets('removing one of two overlapping tags keeps the shared '
          'person', (tester) async {
        final forward = await startPost(tester);
        await pumpSheet(tester, size: size);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_tagChip('Tc')));
        await tester.pumpAndSettle();
        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ud', 'Ue'});

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();

        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ud', 'Ue'});
        expect(forward.state.selectedIds, composer.selection.selected);
      });

      testWidgets('a person added individually stays when the tag is '
          'removed', (tester) async {
        final forward = await startPost(tester);
        await pumpSheet(tester, size: size);
        composer
          ..toggleManualSelection()
          ..toggleMapRecipient('Ud');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();

        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ud'});
        expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ud'});
      });

      testWidgets('a recipient chip × takes a tag-picked person out of '
          'the selection', (tester) async {
        final forward = await startPost(tester);
        await pumpSheet(tester, size: size);

        await tester.tap(find.byKey(_tagChip('Tn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('constellation.composer.chip_remove.Ud')),
        );
        await tester.pumpAndSettle();

        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
        expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc'});
      });
    });
  }

  testWidgets('without people tags the sheet shows no tag chips', (
    tester,
  ) async {
    await GetIt.I.unregister<PeopleTagsCase>();
    await startPost(tester);
    await pumpSheet(tester, size: narrow);

    expect(find.byKey(_tagChip('Tn')), findsNothing);
    expect(find.byKey(_autoChip(5)), findsNothing);
    expect(find.byKey(_recipientChip('Ua')), findsOneWidget);
  });
}
