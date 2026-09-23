import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../../ui/effect/fake_ui_effect_port.dart';

const kRefEgo = Profile(id: 'ego', displayName: 'Vadim');

const _refPeers = [
  ConstellationPerson(id: 'am', displayName: 'agent m9x4u2k7'),
  ConstellationPerson(id: 'in', displayName: 'invite6'),
  ConstellationPerson(id: 'sm', displayName: 'SurmatMG'),
];

const _refTier1Edges = [
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'in', tier: 1),
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'sm', tier: 1),
];

const _allEgoReferenceRequests = [
  ConstellationRequest(
    id: 'req-ego-1',
    authorId: 'ego',
    title: 'Тентура: Autumn release planning',
    status: 0,
    isMine: true,
  ),
  ConstellationRequest(
    id: 'req-ego-2',
    authorId: 'ego',
    title: 'Tentura: UI polish pass before the release',
    status: 0,
    isMine: true,
  ),
  ConstellationRequest(
    id: 'req-ego-3',
    authorId: 'ego',
    title: 'blabla',
    status: 0,
    isMine: true,
  ),
  ConstellationRequest(
    id: 'req-ego-4',
    authorId: 'ego',
    title:
        'Длинный заголовок / Long mixed-script title for layout stress req-ego-4',
    status: 0,
    isMine: true,
  ),
  ConstellationRequest(
    id: 'req-ego-5',
    authorId: 'ego',
    title:
        'Тентура Tentura テスト test — ещё один длинный заголовок req-ego-5',
    status: 0,
    isMine: true,
  ),
  ConstellationRequest(
    id: 'req-ego-6',
    authorId: 'ego',
    title:
        'Mixed EN/RU/数字123 overflow probe title for reference fixture req-ego-6',
    status: 0,
    isMine: true,
  ),
];

const _satelliteReferenceRequests = [
  ConstellationRequest(
    id: 'req-am-1',
    authorId: 'am',
    title: 'Test Beacon',
    status: 0,
  ),
  ConstellationRequest(
    id: 'req-in-1',
    authorId: 'in',
    title: 'Blabla',
    status: 0,
  ),
  ConstellationRequest(
    id: 'req-in-2',
    authorId: 'in',
    title: 'didjdjeh',
    status: 0,
  ),
  ConstellationRequest(
    id: 'req-sm-1',
    authorId: 'sm',
    title: 'I need documents translated into English for the visa office',
    status: 0,
  ),
];

/// Reference constellation field for UI remediation (plan R00).
///
/// Optional [anchors]: when non-null, attaches [ConstellationAnchorProjection]
/// (same shape as `constellation_anchor_interaction_test.dart` `_field`).
/// R03 can pin `req-in-2` via `ConstellationAnchorTarget.beacon('req-in-2')`
/// and person `am` via `ConstellationAnchorTarget.person('am')`.
ConstellationField constellationReferenceField({
  int egoRequestCount = 6,
  List<ConstellationAnchor>? anchors,
}) {
  final clampedEgoCount = egoRequestCount.clamp(0, _allEgoReferenceRequests.length);
  final requests = [
    ..._allEgoReferenceRequests.take(clampedEgoCount),
    ..._satelliteReferenceRequests,
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peers: _refPeers,
    edges: _refTier1Edges,
    requests: requests,
    anchorProjection: anchors == null
        ? null
        : ConstellationAnchorProjection(
            revision: ConstellationAnchorRevision(BigInt.one),
            anchors: anchors,
            pinnedPeers: _refPeers,
            pinnedRequests: requests,
            supportPeers: const [],
            supportEdges: const [],
            serverFilteredBeaconIds: const [],
            serverFilteredBeaconCount: 0,
          ),
  );
}

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

ConstellationFieldCase constellationCaseForField(ConstellationField field) =>
    ConstellationFieldCase(
      _StubRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationReferenceFixture'),
    );

Future<ConstellationCubit> loadReferenceCubit({ConstellationField? field}) async {
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(field ?? constellationReferenceField()),
    viewer: kRefEgo,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    emit(
      state.copyWith(
        selectedProfile: profile,
        dismissedFocusId: null,
      ),
    );
  }

  @override
  void dismiss() {
    final id = state.selectedProfile?.id;
    if (id == null || id.isEmpty) {
      return;
    }
    emit(state.copyWith(dismissedFocusId: id));
  }

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
}

Future<FakeUiEffectPort> pumpConstellationBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Size size = const Size(375, 547),
  double textScale = 1.0,
  TextScaler? textScaler,
  Locale locale = const Locale('ru'),
  ThemeData? theme,
  FakeUiEffectPort? effects,
  ConstellationPresentationFrameHolder? presentationFrameHolder,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  final resolvedScaler = textScaler ?? TextScaler.linear(textScale);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fx = effects ?? FakeUiEffectPort();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: theme ?? TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: resolvedScaler,
          ),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _StubContextCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(fx),
                ),
              ],
              child: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
                presentationFrameHolder: presentationFrameHolder,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return fx;
}
