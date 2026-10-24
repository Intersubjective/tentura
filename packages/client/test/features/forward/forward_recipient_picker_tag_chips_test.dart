import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

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
    // 'blocked' is unreachable and 'sent' was already forwarded by the viewer.
    PersonTagMembers(
      tagId: 'Tn',
      personIds: ['alex', 'blocked', 'sent'],
    ),
    PersonTagMembers(tagId: 'Tc', personIds: ['alex', 'lena']),
  ];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [
    PersonAutoTag(kind: 3, count: 1, showInFilters: true),
    PersonAutoTag(kind: 5, count: 2, showInFilters: true),
  ];

  @override
  Future<List<String>> personAutoTagMembers(int kind) async => switch (kind) {
    3 => ['lena'],
    5 => ['alex', 'o2'],
    _ => [],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ForwardCandidate _candidate(
  String id, {
  double score = 1,
  bool reachable = true,
  CandidateInvolvement involvement = CandidateInvolvement.unseen,
  List<String> topCapabilities = const [],
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: id,
    score: reachable ? score : 0,
    rScore: reachable ? 1 : 0,
  ),
  involvement: involvement,
  topCapabilities: topCapabilities,
);

ValueKey<String> _chip(String tagId) => ValueKey('forward-tag-chip-$tagId');

ValueKey<String> _outsideHintRow(String id) =>
    ValueKey('forward-tag-outside-$id');

const _note = ValueKey('forward-tag-note');

/// Automatic tags: kind 3 is "Helped me", kind 5 is "Worked together".
ValueKey<String> _autoChip(int kind) => ValueKey('forward-tag-chip-auto-$kind');

String _arbText(String key) =>
    (jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>)[key]!
        as String;
const _outsideHint = ValueKey('forward-tag-outside-hint');

Finder _checkbox(String id) =>
    find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox(id)));

/// [embedded] is how the Post/Request composer's recipients step hosts the
/// picker (host-provided send button); otherwise the forward screen's form.
Future<ForwardCubit> _pump(
  WidgetTester tester, {
  required bool embedded,
  List<ForwardCandidate>? candidates,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = ForwardCubit(
    beaconId: 'B1',
    debugSkipInitialLoad: true,
    embedded: embedded,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  cubit.emit(
    ForwardState(
      beaconId: 'B1',
      beacon: Beacon.empty.copyWith(id: 'B1', title: 'T', needs: {'tools'}),
      activeFilter: ForwardFilter.all,
      candidates:
          candidates ??
          [
            _candidate('alex'),
            _candidate('lena'),
            _candidate('blocked', reachable: false),
            _candidate('sent', involvement: CandidateInvolvement.forwardedByMe),
            _candidate('o1', score: 1, topCapabilities: ['tools']),
            _candidate('o2', score: 2),
            _candidate('o3', score: 3),
            _candidate('o4', score: 4),
          ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
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
        child: Scaffold(
          body: BlocBuilder<ForwardCubit, ForwardState>(
            builder: (context, state) => ForwardRecipientPicker(
              beaconId: 'B1',
              embedded: embedded,
              onSendPressed: embedded ? () {} : null,
              sendEnabled: state.selectedIds.isNotEmpty,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
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
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  for (final embedded in [false, true]) {
    final where = embedded ? 'composer recipients step' : 'forward screen';

    group('tag chips in the $where', () {
      testWidgets('show one chip per own tag above the list', (tester) async {
        await _pump(tester, embedded: embedded);

        expect(find.byKey(_chip('Tn')), findsOneWidget);
        expect(find.byKey(_chip('Tc')), findsOneWidget);
        expect(find.text('Neighbours'), findsWidgets);
      });

      testWidgets(
        'show Helped me and Worked together chips after the own tags',
        (tester) async {
          await _pump(tester, embedded: embedded);

          expect(find.byKey(_autoChip(3)), findsOneWidget);
          expect(find.byKey(_autoChip(5)), findsOneWidget);
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
          for (final own in [_chip('Tn'), _chip('Tc')]) {
            for (final auto in [_autoChip(3), _autoChip(5)]) {
              final a = at(own);
              final b = at(auto);
              expect(a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx), isTrue);
            }
          }
          expect(find.byKey(_autoChip(3)).evaluate(), isNotEmpty);
        },
      );

      testWidgets('an automatic chip toggles its eligible members', (
        tester,
      ) async {
        final cubit = await _pump(tester, embedded: embedded);

        await tester.tap(_checkbox('alex'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_autoChip(5)));
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {'alex', 'o2'});

        await tester.tap(find.byKey(_autoChip(5)));
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {'alex'});
      });

      testWidgets('tapping a tag selects only its eligible members', (
        tester,
      ) async {
        final cubit = await _pump(tester, embedded: embedded);

        await tester.tap(find.byKey(_chip('Tn')));
        await tester.pumpAndSettle();

        expect(cubit.state.selectedIds, {'alex'});
      });

      testWidgets(
        'members who cannot be forwarded to show their usual reason label',
        (tester) async {
          await _pump(tester, embedded: embedded);
          await tester.tap(find.byKey(_chip('Tn')));
          await tester.pumpAndSettle();
          final l10n = L10nEn();

          expect(
            find.descendant(
              of: find.byKey(TestIds.key(TestIds.forwardRecipient('blocked'))),
              matching: find.text(l10n.notReachable),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(TestIds.key(TestIds.forwardRecipient('sent'))),
              matching: find.text(l10n.forwardedByMe),
            ),
            findsOneWidget,
          );
          // The row's checkbox is a custom widget, not a Material Checkbox.
          for (final id in ['blocked', 'sent']) {
            expect(
              tester.getSemantics(_checkbox(id)),
              isSemantics(
                hasCheckedState: true,
                isChecked: false,
                hasEnabledState: true,
                isEnabled: false,
              ),
            );
          }

          Color? nameColor(String id) => tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(TestIds.key(TestIds.forwardRecipient(id))),
                  matching: find.text(id),
                ),
              )
              .style
              ?.color;
          final muted = tester
              .element(
                find.byKey(TestIds.key(TestIds.forwardRecipient('lena'))),
              )
              .tt
              .textMuted;
          expect(nameColor('blocked'), muted);
          expect(nameColor('sent'), muted);
          expect(nameColor('lena'), isNot(muted));
        },
      );

      testWidgets('tapping the tag again removes only people it added', (
        tester,
      ) async {
        final cubit = await _pump(tester, embedded: embedded);

        // 'lena' is picked by hand first; Climbers then adds 'alex' only.
        await tester.tap(_checkbox('lena'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_chip('Tc')));
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {'alex', 'lena'});

        await tester.tap(find.byKey(_chip('Tc')));
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {'lena'});
      });

      testWidgets('selecting a tag shows at most three outside-tag helpers', (
        tester,
      ) async {
        await _pump(tester, embedded: embedded);
        expect(find.byKey(_outsideHint), findsNothing);

        await tester.tap(find.byKey(_chip('Tn')));
        await tester.pumpAndSettle();

        expect(find.byKey(_outsideHint), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_outsideHint),
            matching: find.text('Outside the tag, could help'),
          ),
          findsOneWidget,
        );
        final rows = [
          for (final id in ['lena', 'o1', 'o2', 'o3', 'o4'])
            if (find.byKey(_outsideHintRow(id)).evaluate().isNotEmpty) id,
        ];
        expect(rows, hasLength(3));
        // Request needs 'tools': the capability match leads, then score.
        expect(rows.first, 'o1');
        expect(find.byKey(_outsideHintRow('alex')), findsNothing);
        expect(find.byKey(_outsideHintRow('blocked')), findsNothing);
      });

      testWidgets('the individual-forward note is visible', (tester) async {
        await _pump(tester, embedded: embedded);

        expect(find.byKey(_note), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_note),
            matching: find.text(_arbText('peopleTagsForwardNote')),
          ),
          findsOneWidget,
        );
      });
    });
  }
}
