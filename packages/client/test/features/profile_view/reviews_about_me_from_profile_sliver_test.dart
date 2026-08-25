import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluations_written_about_viewer.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_reviews_about_me_cubit.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/reviews_about_me_from_profile_sliver.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

EvaluationsWrittenAboutViewerRow _row({
  required String beaconTitle,
  required EvaluationReceivedTrustTone trustTone,
  String beaconId = 'B1',
  String note = '',
  int value = 5,
  List<String> acknowledgedHelpTags = const [],
}) => EvaluationsWrittenAboutViewerRow(
  beaconId: beaconId,
  beaconTitle: beaconTitle,
  evaluatorId: 'U-owner',
  evaluatedUserId: 'U-me',
  value: value,
  trustTone: trustTone,
  occurredAt: DateTime.utc(2026, 1, 1),
  note: note,
  acknowledgedHelpTags: acknowledgedHelpTags,
);

class _FakeProfileReviewsAboutMeCubit extends ProfileReviewsAboutMeCubit {
  _FakeProfileReviewsAboutMeCubit(ProfileReviewsAboutMeState seed)
    : super(
        profileOwnerId: 'U-owner',
        evaluationRepository: _MinimalEvaluationRepository(),
      ) {
    emit(seed);
  }

  @override
  Future<void> fetch({bool showLoading = true}) async {}
}

class _MinimalEvaluationRepository implements EvaluationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _StubProfileRepository implements ProfileRepositoryPort {
  _StubProfileRepository(this.displayName);

  final String displayName;

  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: displayName);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProfileViewCubit _profileViewCubit(String displayName) {
  final realtime = buildTestRealtimeSync();
  final authCase = buildTestAuthCase(StreamingAuthLocal(), EmptyAuthRemote());
  final contactsCase = ContactsCase(
    FakeContactsRepository(),
    authCase,
    ContactNameStore(),
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final case_ = ProfileViewCase(
    _StubProfileRepository(displayName),
    _StubLikeRepository(),
    _StubCapabilityRepository(),
    contactsCase,
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final cubit = ProfileViewCubit.test(
    id: 'U-owner',
    profileViewCase: case_,
    blockCase: ControllableBlockCase(),
    effects: FakeUiEffectPort(),
    autoFetch: false,
  );
  cubit.emit(
    ProfileViewState(
      profile: Profile(id: 'U-owner', displayName: displayName),
    ),
  );
  return cubit;
}

final class _StubLikeRepository implements LikeRemoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _StubCapabilityRepository implements CapabilityRepositoryPort {
  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pumpSliver(
  WidgetTester tester, {
  required ProfileReviewsAboutMeState reviewsState,
  String profileOwnerName = 'Bota N.',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileViewCubit>.value(
              value: _profileViewCubit(profileOwnerName),
            ),
            BlocProvider<ProfileReviewsAboutMeCubit>.value(
              value: _FakeProfileReviewsAboutMeCubit(reviewsState),
            ),
          ],
          child: const Scaffold(
            body: CustomScrollView(
              slivers: [ReviewsAboutMeFromProfileSliver()],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ReviewsAboutMeFromProfileSliver', () {
    testWidgets('renders rows with trust tone icons and section header', (
      tester,
    ) async {
      await _pumpSliver(
        tester,
        reviewsState: ProfileReviewsAboutMeState(
          status: StateStatus.isSuccess,
          rows: [
            _row(
              beaconTitle: 'Move help this weekend',
              trustTone: EvaluationReceivedTrustTone.up,
              note: 'fast, careful',
              value: 5,
              acknowledgedHelpTags: const ['transport', 'pets', 'storage'],
            ),
            _row(
              beaconTitle: 'Errand run downtown',
              trustTone: EvaluationReceivedTrustTone.down,
              beaconId: 'B2',
              value: 2,
            ),
          ],
        ),
      );

      expect(find.text('Reviews from Bota N.'), findsOneWidget);
      expect(find.text('Move help this weekend'), findsOneWidget);
      expect(find.text('Errand run downtown'), findsOneWidget);
      expect(find.text('Helped a lot'), findsOneWidget);
      expect(find.text('Hurt somewhat'), findsOneWidget);
      expect(find.text('🤩'), findsOneWidget);
      expect(find.text('👎'), findsOneWidget);
      expect(find.text('Transport, Storage +1'), findsOneWidget);
      expect(find.text('fast, careful'), findsOneWidget);
    });

    testWidgets('empty rows render nothing without section header', (
      tester,
    ) async {
      await _pumpSliver(
        tester,
        reviewsState: const ProfileReviewsAboutMeState(
          status: StateStatus.isSuccess,
          rows: [],
        ),
      );

      expect(find.text('Reviews from Bota N.'), findsNothing);
      expect(find.byType(LinearPiActive), findsNothing);
    });

    testWidgets('loading state shows progress indicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileViewCubit>.value(
                  value: _profileViewCubit('Bota N.'),
                ),
                BlocProvider<ProfileReviewsAboutMeCubit>.value(
                  value: _FakeProfileReviewsAboutMeCubit(
                    const ProfileReviewsAboutMeState(
                      status: StateStatus.isLoading,
                      rows: [],
                    ),
                  ),
                ),
              ],
              child: const Scaffold(
                body: CustomScrollView(
                  slivers: [ReviewsAboutMeFromProfileSliver()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LinearPiActive), findsOneWidget);
      expect(find.text('Reviews from Bota N.'), findsNothing);
    });
  });
}
