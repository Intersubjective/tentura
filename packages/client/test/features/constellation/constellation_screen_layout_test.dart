import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

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

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: const [
            ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      ),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationScreenLayoutTest'),
    ),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('ConstellationScreen desktop centering', () {
    testWidgets(
      'app bar sits in the centered column while the graph canvas is full-bleed',
      (tester) async {
        const size = Size(1280, 800);
        const contentMaxWidth = 720.0;
        final cubit = await _loadCubit();
        await _pumpScreen(tester, cubit: cubit, size: size);

        final bodyRect = tester.getRect(find.byType(ConstellationBody));
        expect(bodyRect.width, closeTo(size.width, 1));
        expect(bodyRect.left, closeTo(0, 1));

        final columnLeft = (size.width - contentMaxWidth) / 2;
        final columnRight = columnLeft + contentMaxWidth;
        final toggle = find.byKey(const Key('constellation.app_bar.view_mode'));
        final filters = find.byKey(const Key('constellation.app_bar.filters'));
        expect(tester.getRect(toggle).right, lessThanOrEqualTo(columnRight + 1));
        expect(
          tester.getRect(toggle).left,
          greaterThanOrEqualTo(columnLeft - 1),
        );
        expect(
          tester.getRect(filters).right,
          lessThanOrEqualTo(columnRight + 1),
        );
        expect(
          tester.getRect(filters).left,
          greaterThanOrEqualTo(columnLeft - 1),
        );
        await cubit.close();
      },
    );

    testWidgets('compact keeps the graph full-bleed', (tester) async {
      const size = Size(390, 800);
      final cubit = await _loadCubit();
      await _pumpScreen(tester, cubit: cubit, size: size);

      final bodyRect = tester.getRect(find.byType(ConstellationBody));
      expect(bodyRect.width, closeTo(size.width, 1));
      expect(bodyRect.left, closeTo(0, 1));
      await cubit.close();
    });
  });
}
