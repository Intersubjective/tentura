// Opening the Request form with a Post to convert (`convertFromPostId`, plus
// the discoverability picked in the confirmation) builds the form's cubit in
// conversion mode: the Post's root message is fetched and prefills the form,
// and the dialog's choice is what a later submit sends. Without the parameter
// the form is the ordinary create form and touches no Post.
// The route wrapper (`BeaconCreateScreen.wrappedRoute`) builds its cubits from
// GetIt, so this runs the real wrapper over fakes.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

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

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

class _FakePostConversionPort implements PostConversionPort {
  final fetchedIds = <String>[];
  final convertedIds = <String>[];
  final convertedDiscoverable = <bool>[];

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
    List<String> helperIds = const [],
  }) async {
    convertedIds.add(beaconId);
    convertedDiscoverable.add(isDiscoverable);
  }
}

Future<({_FakePostConversionPort port, BeaconCreateCubit cubit})> _pumpScreen(
  WidgetTester tester, {
  String convertFromPostId = '',
  bool convertIsDiscoverable = true,
}) async {
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

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: Builder(
            builder: (context) => BeaconCreateScreen(
              convertFromPostId: convertFromPostId,
              convertIsDiscoverable: convertIsDiscoverable,
            ).wrappedRoute(context),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final cubit = tester
      .element(find.byType(BeaconCreateScreen))
      .read<BeaconCreateCubit>();
  return (port: port, cubit: cubit);
}

void main() {
  testWidgets('the form opened for a Post is prefilled from its root message', (tester) async {
    final opened = await _pumpScreen(tester, convertFromPostId: _postId);

    expect(opened.port.fetchedIds, [_postId]);
    expect(opened.cubit.state.title, 'Need a ladder');
    expect(opened.cubit.state.description, 'I can pick it up.');
  });

  testWidgets('the discoverability from the confirmation reaches the conversion', (tester) async {
    final opened = await _pumpScreen(
      tester,
      convertFromPostId: _postId,
      convertIsDiscoverable: false,
    );

    expect(opened.cubit.state.isDiscoverable, isFalse);

    await opened.cubit.submitConversion();

    expect(opened.port.convertedIds, [_postId]);
    expect(opened.port.convertedDiscoverable, [false]);
  });

  testWidgets('a discoverable confirmation keeps the Request discoverable', (tester) async {
    final opened = await _pumpScreen(tester, convertFromPostId: _postId);

    await opened.cubit.submitConversion();

    expect(opened.port.convertedDiscoverable, [true]);
  });

  testWidgets('the ordinary create form does not touch any Post', (tester) async {
    final opened = await _pumpScreen(tester);

    expect(opened.port.fetchedIds, isEmpty);
    expect(opened.cubit.state.title, isEmpty);
    expect(opened.port.convertedIds, isEmpty);
  });
}
