import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart'
    show kLazyWriteAckTimeout;
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/like/domain/exception.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/graph_trust_write_fixture.dart';

const _bob = Profile(id: 'Ub', displayName: 'Bob');

class _FieldRepository implements ConstellationRepositoryPort {
  int reads = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    reads++;
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 10),
      context: '',
      peers: const [ConstellationPerson(id: 'Ub', displayName: 'Bob')],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'Ub', dst: 'Ume', tier: 1),
      ],
    );
  }
}

final _toggle = find.byKey(TestIds.key(TestIds.graphPersonContextTrust));

Future<({GraphTrustWriteFixture trust, _FieldRepository field})> _openBobPanel(
  WidgetTester tester,
) async {
  const size = Size(1200, 800);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final trust = GraphTrustWriteFixture();
  trust.profiles.byId['Ub'] = _bob;
  final field = _FieldRepository();
  final store = ConstellationStoreFixture(field, accountId: 'Ume');
  final constellation = store.createCubit(
    viewer: const Profile(id: 'Ume', displayName: 'Me'),
  );
  final context = trust.createCubit();
  final composer = ConstellationComposerCubit(
    positions: const {},
    eligible: const {},
    createCubitFactory: (_) =>
        throw StateError('Composer not used in trust tests'),
    forwardCubitFactory: (_) =>
        throw StateError('Composer not used in trust tests'),
  );
  addTearDown(constellation.close);
  addTearDown(trust.dispose);
  addTearDown(composer.close);
  // The fixture deliberately disables loadOnCreate; explicitly load the field
  // instead of waiting for an event that no producer can emit.
  await tester.pump();
  constellation.setVisible(true);
  await tester.runAsync(constellation.load);
  expect(constellation.state.status, isA<StateIsSuccess>());
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: constellation),
              BlocProvider<GraphPersonContextCubit>.value(value: context),
              BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider<HomeTabReselectCubit>(
                create: (_) => HomeTabReselectCubit(),
              ),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  trust.account.add('Ume');
  constellation.selectPerson('Ub');
  context.selectProfile(_bob, intentional: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_toggle, findsOneWidget);
  expect(tester.widget<Switch>(_toggle).value, isFalse);
  return (trust: trust, field: field);
}

void main() {
  group('Constellation person context trust', () {
    testWidgets(
      'toggle changes immediately and remains enabled without progress',
      (tester) async {
        final harness = await _openBobPanel(tester);
        final reads = harness.field.reads;
        final profileReads = harness.trust.profiles.fetchCalls;
        await tester.tap(_toggle);
        await tester.pump();
        expect(tester.widget<Switch>(_toggle).value, isTrue);
        expect(tester.widget<Switch>(_toggle).onChanged, isNotNull);
        expect(
          find.descendant(
            of: find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(harness.trust.likes.amounts, [1]);
        harness.trust.likes.ack(0);
        await tester.pump();
        expect(harness.field.reads, reads);
        expect(harness.trust.profiles.fetchCalls, profileReads);
      },
    );

    testWidgets(
      'rejection reverts the toggle and Retry sends the intended value',
      (tester) async {
        final harness = await _openBobPanel(tester);
        await tester.tap(_toggle);
        await tester.pump();
        harness.trust.likes.fail(0, const LikeSetException());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Switch>(_toggle).value, isFalse);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Trust change not saved'), findsOneWidget);
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await tester.pump();
        expect(tester.widget<Switch>(_toggle).value, isTrue);
        expect(harness.trust.likes.amounts, [1, 1]);
      },
    );

    testWidgets('exhausted transport retries revert trust and offer Retry', (
      tester,
    ) async {
      final harness = await _openBobPanel(tester);
      await tester.tap(_toggle);
      await tester.pump();
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(harness.trust.likes.calls, hasLength(attempt + 1));
        final schedulesBeforeFailure = harness.trust.wakeUp.calls.length;
        harness.trust.likes.fail(
          attempt,
          TimeoutException('no acknowledgement'),
        );
        await tester.pump();
        if (attempt < 2) {
          final delay = expectR4RetryScheduled(
            harness.trust.wakeUp,
            schedulesBeforeFailure,
            attempt: attempt + 1,
          );
          harness.trust.wakeUp.elapse(delay - const Duration(milliseconds: 1));
          await tester.pump();
          expect(harness.trust.likes.calls, hasLength(attempt + 1));
          harness.trust.wakeUp.elapse(const Duration(milliseconds: 1));
          await tester.pump();
        }
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Switch>(_toggle).value, isFalse);
      expect(
        find.widgetWithText(SnackBar, 'Trust change not saved'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await tester.pump();
      expect(harness.trust.likes.amounts, [1, 1, 1, 1]);
      expect(tester.widget<Switch>(_toggle).value, isTrue);
    });

    testWidgets(
      'an unacknowledged trust change raises one notice after fifteen seconds',
      (tester) async {
        final harness = await _openBobPanel(tester);
        await tester.tap(_toggle);
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);
        harness.trust.wakeUp.elapse(
          kLazyWriteAckTimeout - const Duration(milliseconds: 1),
        );
        await tester.pump(
          kLazyWriteAckTimeout - const Duration(milliseconds: 1),
        );
        expect(find.byType(SnackBar), findsNothing);
        harness.trust.wakeUp.elapse(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
        final l10n = L10n.of(tester.element(_toggle))!;
        expect(find.text(l10n.lazyWriteAckOverdue), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(tester.widget<Switch>(_toggle).onChanged, isNotNull);
      },
    );
  });
}
