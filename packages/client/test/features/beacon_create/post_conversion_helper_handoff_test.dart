import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/post_conversion_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_conversion_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import 'fake_beacon_ports.dart';

const _postId = 'post-1';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

// Mounts the real generated page, including WrappedRoute and cubit creation.
class _ConversionRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: BeaconCreateRoute.page, path: kPathBeaconNew),
  ];
}

class _FakePostConversionPort implements PostConversionPort {
  final fetchedIds = <String>[];
  final convertedIds = <String>[];
  final convertedDiscoverable = <bool>[];
  final convertedHelpers = <List<String>?>[];

  @override
  Future<PostRootContent> fetchRootContent(String beaconId) async {
    fetchedIds.add(beaconId);
    return const PostRootContent(body: 'Need a ladder\nI can pick it up.');
  }

  @override
  Future<void> convertToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String>? helperIds,
  }) async {
    convertedIds.add(beaconId);
    convertedDiscoverable.add(isDiscoverable);
    convertedHelpers.add(helperIds == null ? null : List.of(helperIds));
  }
}

typedef ConversionRouteHarness = ({
  BeaconCreateCubit cubit,
  List<String> fetchedIds,
  List<String> convertedIds,
  List<bool> convertedDiscoverable,
  List<List<String>?> convertedHelpers,
});

/// Builds the production generated route supplied by the caller. This also
/// lets the confirmation widget test submit the exact route it emitted.
Future<ConversionRouteHarness> pumpConversionRoute(
  WidgetTester tester,
  PageRouteInfo route,
) async {
  final port = _FakePostConversionPort();
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
    ..registerSingleton<BeaconCreateCase>(fakeBeaconCreateCase())
    ..registerSingleton<PostConversionCase>(PostConversionCase(port));
  addTearDown(GetIt.I.reset);
  final router = _ConversionRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      routerConfig: router.config(
        deepLinkBuilder: (_) => DeepLink([route]),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(BeaconCreateScreen), findsOneWidget);
  final cubit = tester
      .element(find.byType(BeaconCreateScreen))
      .read<BeaconCreateCubit>();
  return (
    cubit: cubit,
    fetchedIds: port.fetchedIds,
    convertedIds: port.convertedIds,
    convertedDiscoverable: port.convertedDiscoverable,
    convertedHelpers: port.convertedHelpers,
  );
}

Future<ConversionRouteHarness> _pumpRoute(
  WidgetTester tester, {
  String convertFromPostId = '',
  bool convertIsDiscoverable = true,
  List<String>? convertHelperIds,
}) async {
  BeaconCreateRoute route;
  // Keep the tests runnable before the generated route accepts helper ids.
  try {
    route =
        Function.apply(BeaconCreateRoute.new, const [], {
              #convertFromPostId: convertFromPostId,
              #convertIsDiscoverable: convertIsDiscoverable,
              if (convertHelperIds != null) #convertHelperIds: convertHelperIds,
            })
            as BeaconCreateRoute;
  } on NoSuchMethodError {
    fail('The generated Request route must accept the chosen helper ids');
  }
  return pumpConversionRoute(tester, route);
}

void main() {
  group('Request navigation carries post conversion helpers', () {
    testWidgets(
      'generated navigation passes exactly the chosen helpers through the cubit to the conversion repository port',
      (tester) async {
        final opened = await _pumpRoute(
          tester,
          convertFromPostId: _postId,
          convertHelperIds: ['Ureader', 'Usecond'],
          convertIsDiscoverable: false,
        );
        expect(opened.convertedIds, isEmpty);
        expect(await opened.cubit.submitConversion(), _postId);
        expect(opened.convertedIds, [_postId]);
        expect(opened.convertedHelpers, [
          unorderedEquals(['Ureader', 'Usecond']),
        ]);
        expect(opened.convertedDiscoverable, [false]);
      },
    );

    testWidgets(
      'submitting a route with an explicit empty helper selection passes an empty list to the conversion repository port',
      (tester) async {
        final opened = await _pumpRoute(
          tester,
          convertFromPostId: _postId,
          convertHelperIds: const [],
        );
        expect(opened.fetchedIds, [_postId]);
        expect(opened.convertedIds, isEmpty);
        expect(await opened.cubit.submitConversion(), _postId);
        expect(opened.convertedIds, [_postId]);
        expect(opened.convertedHelpers, [<String>[]]);
      },
    );

    testWidgets(
      'submitting without selected helpers passes an empty list rather than omitting it',
      (tester) async {
        final opened = await _pumpRoute(tester, convertFromPostId: _postId);
        expect(await opened.cubit.submitConversion(), _postId);
        expect(opened.convertedIds, [_postId]);
        expect(opened.convertedHelpers, [isEmpty]);
      },
    );
  });
}
