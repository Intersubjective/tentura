import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_label.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {}
}

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 13),
        context: '',
      );
}

Future<ConstellationCubit> _previewCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPreviewTest'),
    ),
    viewer: _ego,
    loadOnCreate: false,
  );
  await cubit.load();
  return cubit;
}

const _forbiddenFragments = <String>[
  'from ',
  'via ',
  ' shared',
  ' has not seen',
  'recommended',
  'top',
  'trending',
];

ConstellationRequest _request({
  required String id,
  int status = 0,
  ConstellationHeldState held = ConstellationHeldState.none,
  String title = 'Borrow a drill',
  DateTime? startAt,
}) {
  return ConstellationRequest(
    id: id,
    authorId: 'author',
    title: title,
    status: status,
    startAt: startAt,
    isMine: held == ConstellationHeldState.mine,
    viewerHasActiveHelpOffer: held == ConstellationHeldState.offered,
    viewerIsRoomParticipant: held == ConstellationHeldState.participant,
    viewerHasForwardEdge: held == ConstellationHeldState.forwarded,
  );
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  required ConstellationRequest request,
  String connectionThroughName = 'Bob',
}) async {
  final cubit = await _previewCubit();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<ConstellationCubit>.value(
          value: cubit,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showConstellationRequestPreviewSheet(
                    context: context,
                    request: request,
                    authorDisplayName: 'Ann',
                    connectionThroughName: connectionThroughName,
                    onOpen: () {},
                    onPrimaryAction: () {},
                    onForward: () {},
                    now: DateTime.utc(2026, 9, 13, 12),
                  ),
                  child: const Text('Open preview'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open preview'));
  await tester.pumpAndSettle();
}

List<String> _allRenderedStrings(WidgetTester tester) {
  final values = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = element.widget as Text;
    final text = data.data;
    if (text != null && text.isNotEmpty) {
      values.add(text);
    }
  }
  return values;
}

void _assertNoForbiddenCopy(Iterable<String> strings) {
  for (final value in strings) {
    final lower = value.toLowerCase();
    for (final fragment in _forbiddenFragments) {
      expect(
        lower.contains(fragment),
        isFalse,
        reason: 'Forbidden fragment "$fragment" in "$value"',
      );
    }
  }
}

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('constellationPreviewPrimaryActionLabel', () {
    const statuses = <int, String>{
      0: 'open',
      7: 'needsMoreHelp',
      8: 'enoughHelp',
    };

    const heldStates = <ConstellationHeldState, String>{
      ConstellationHeldState.none: 'none',
      ConstellationHeldState.offered: 'offered',
      ConstellationHeldState.participant: 'participant',
      ConstellationHeldState.mine: 'mine',
    };

    for (final statusEntry in statuses.entries) {
      for (final heldEntry in heldStates.entries) {
        test(
          '${statusEntry.value} × ${heldEntry.value} primary action',
          () {
            final request = _request(
              id: 'r',
              status: statusEntry.key,
              held: heldEntry.key,
            );
            final label = constellationPreviewPrimaryActionLabel(l10n, request);

            final expected = switch (heldEntry.key) {
              ConstellationHeldState.mine => l10n.openBeacon,
              ConstellationHeldState.offered => l10n.beaconCtaEditHelpOffer,
              ConstellationHeldState.participant => l10n.openBeacon,
              ConstellationHeldState.none => statusEntry.key == 8
                  ? l10n.beaconOfferHelpAsBackup
                  : l10n.labelOfferHelp,
              ConstellationHeldState.forwarded => l10n.openBeacon,
            };

            expect(label, expected);
          },
        );
      }
    }
  });

  group('CTA dedup', () {
    testWidgets(
      'hides outlined Open when primary label is also Open',
      (tester) async {
        await _pumpPreview(
          tester,
          request: _request(
            id: 'fwd',
            held: ConstellationHeldState.forwarded,
          ),
        );

        expect(find.text(l10n.openBeacon), findsOneWidget);
        expect(find.widgetWithText(FilledButton, l10n.openBeacon), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, l10n.openBeacon), findsNothing);
      },
    );

    testWidgets(
      'keeps outlined Open when primary is a different action',
      (tester) async {
        await _pumpPreview(
          tester,
          request: _request(
            id: 'new',
            held: ConstellationHeldState.none,
          ),
        );

        expect(find.widgetWithText(OutlinedButton, l10n.openBeacon), findsOneWidget);
        expect(find.widgetWithText(FilledButton, l10n.labelOfferHelp), findsOneWidget);
      },
    );
  });

  group('forbidden copy', () {
    testWidgets('preview sheet renders no forbidden strings', (tester) async {
      await _pumpPreview(
        tester,
        request: _request(
          id: 'r1',
          status: 8,
          startAt: DateTime.utc(2026, 9, 13, 18),
        ),
        connectionThroughName: 'Bob',
      );

      _assertNoForbiddenCopy(_allRenderedStrings(tester));
      expect(
        find.text(l10n.constellationConnectionLabel('Bob')),
        findsOneWidget,
      );
      expect(find.text(l10n.constellationNotReferral), findsOneWidget);
    });

    testWidgets('label widget renders no forbidden strings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: ConstellationRequestLabel(
                request: _request(
                  id: 'r1',
                  status: 8,
                  held: ConstellationHeldState.offered,
                  startAt: DateTime.utc(2026, 9, 13, 18),
                ),
                now: DateTime.utc(2026, 9, 13, 12),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      _assertNoForbiddenCopy(_allRenderedStrings(tester));
    });
  });

  group('held request annotation', () {
    testWidgets('held request label shows annotation and stays visible', (
      tester,
    ) async {
      final request = _request(
        id: 'held',
        held: ConstellationHeldState.offered,
        status: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: ConstellationRequestLabel(request: request),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Borrow a drill'), findsOneWidget);
      expect(find.text(l10n.constellationHeldOffered), findsOneWidget);
    });

    testWidgets('person panel lists held request annotated, not hidden', (
      tester,
    ) async {
      final request = _request(
        id: 'held',
        held: ConstellationHeldState.participant,
      );
      var expanded = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _StubContextCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: GraphPersonContextPanel(
                    profile: const Profile(id: 'peer', displayName: 'Peer'),
                    focusedNode: const UserNode(
                      user: Profile(id: 'peer', displayName: 'Peer'),
                    ),
                    discoverableRequests: [request],
                    requestsExpanded: expanded,
                    onToggleRequestsExpanded: () {
                      setState(() => expanded = !expanded);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(l10n.constellationPersonShowRequests(1)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('constellation.person_expand')));
      await tester.pump();

      expect(find.textContaining('Borrow a drill'), findsOneWidget);
      expect(find.text(l10n.constellationHeldParticipant), findsOneWidget);
    });
  });

  group('connection path', () {
    test('first-hop peer id skips direct authors', () {
      expect(
        constellationConnectionThroughPeerId(
          egoId: 'ego',
          authorId: 'ann',
          parent: const {'ann': 'ego'},
        ),
        isNull,
      );
      expect(
        constellationConnectionThroughPeerId(
          egoId: 'ego',
          authorId: 'carol',
          parent: const {'carol': 'bob', 'bob': 'ego'},
        ),
        'bob',
      );
    });
  });
}
