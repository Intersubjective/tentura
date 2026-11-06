// #774 tentura-31ve.5: «Help came through A → B → C» on closed Requests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_path_chain_row.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_graph.dart';
import 'package:tentura/features/forward/domain/entity/help_path_node.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _beaconId = 'b-closed-774';
const _authorId = 'u-author';
const _f1Id = 'u-f1';
const _helperId = 'u-helper';
const _strangerId = 'u-stranger';

Profile _p(String id, String name) => Profile(id: id, displayName: name);

Beacon _closedBeacon() => Beacon.empty.copyWith(
  id: _beaconId,
  title: 'Need a van',
  status: BeaconStatus.closed,
  author: _p(_authorId, 'Anna'),
  admittedHelperUsers: [_p(_helperId, 'Vera')],
);

List<HelpPathNode> _multiHopPath({bool blockedMiddle = false}) => [
  const HelpPathNode.named(userId: _authorId, displayName: 'Anna'),
  if (blockedMiddle)
    const HelpPathNode.anonymous(1)
  else
    const HelpPathNode.named(userId: _f1Id, displayName: 'Boris'),
  const HelpPathNode.named(userId: _helperId, displayName: 'Vera'),
];

class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository(this._pathsByHelper);

  final Map<String, List<HelpPathNode>> _pathsByHelper;

  @override
  Future<ForwardGraph> fetchHelpOffererForwardPath({
    required String beaconId,
    required String helpOffererId,
  }) async {
    return ForwardGraph(
      beaconId: beaconId,
      authorId: _authorId,
      path: _pathsByHelper[helpOffererId] ?? const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required BeaconViewState state,
  required FakeUiEffectPort effects,
  required _FakeForwardRepository forwardRepo,
  Locale locale = const Locale('en'),
}) async {
  GetIt.I.registerSingleton<ForwardRepository>(forwardRepo);
  addTearDown(() => GetIt.I.unregister<ForwardRepository>());

  final screen = ScreenCubit(effects);
  addTearDown(screen.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider<ScreenCubit>.value(
        value: screen,
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconOperationalHeaderCard(
              state: state,
              onAuthorTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

void main() {
  testWidgets('author sees Help came through A → F1 → H on closed Request', (
    tester,
  ) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: _multiHopPath(),
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_authorId, 'Anna'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('Help came through'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Boris'), findsOneWidget);
    expect(find.text('Vera'), findsOneWidget);
  });

  testWidgets('forwarder F1 on the path sees the row', (tester) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: _multiHopPath(),
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_f1Id, 'Boris'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('Help came through'), findsOneWidget);
    expect(find.text('Boris'), findsOneWidget);
  });

  testWidgets('involved viewer not on path sees no row', (tester) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: const [],
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_strangerId, 'Kim'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('Help came through'), findsNothing);
  });

  testWidgets('direct author → helper path shows no row', (tester) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: [
        const HelpPathNode.named(userId: _authorId, displayName: 'Anna'),
        const HelpPathNode.named(userId: _helperId, displayName: 'Vera'),
      ],
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_authorId, 'Anna'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('Help came through'), findsNothing);
  });

  testWidgets('blocked participant renders +1', (tester) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: _multiHopPath(blockedMiddle: true),
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_authorId, 'Anna'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('+1'), findsOneWidget);
    expect(find.text('Boris'), findsNothing);
  });

  testWidgets('tap opens ForwardsGraphScreen for the helper', (tester) async {
    final effects = FakeUiEffectPort();
    final forwardRepo = _FakeForwardRepository({
      _helperId: _multiHopPath(),
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_authorId, 'Anna'),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    await tester.tap(find.byType(HelpPathChainRow));
    await tester.pump();

    final push = effects.emitted.whereType<NavigatePush>().last;
    expect(
      push.path,
      '$kPathForwardsGraph/$_beaconId?'
      'committer=${Uri.encodeQueryComponent(_helperId)}'
      '&committerName=${Uri.encodeQueryComponent('Vera')}',
    );
  });

  testWidgets('RU locale at 375×667 renders path without overflow', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final effects = FakeUiEffectPort();
    const longName =
        'Александра Константинопольская с очень длинным именем для проверки';
    final forwardRepo = _FakeForwardRepository({
      _helperId: [
        const HelpPathNode.named(userId: _authorId, displayName: longName),
        const HelpPathNode.named(
          userId: _f1Id,
          displayName: 'Борис Пересылальщиков',
        ),
        const HelpPathNode.named(
          userId: _helperId,
          displayName: 'Вера Помощница',
        ),
      ],
    });
    await _pumpHeader(
      tester,
      effects: effects,
      forwardRepo: forwardRepo,
      locale: const Locale('ru'),
      state: BeaconViewState(
        beacon: _closedBeacon(),
        myProfile: _p(_authorId, longName),
        load: BeaconViewLoad.ready,
        admittedHelperRoster: [_p(_helperId, 'Vera')],
        admittedHelpersLoaded: true,
      ),
    );

    expect(find.text('Помощь прошла через'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rowBox = tester.renderObject<RenderBox>(
      find.byType(HelpPathChainRow),
    );
    expect(rowBox.size.width, lessThanOrEqualTo(375));
  });
}
