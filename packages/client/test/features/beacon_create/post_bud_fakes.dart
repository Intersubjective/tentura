import 'dart:async';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/post_bud_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import 'fake_beacon_ports.dart';

const kBudPostId = 'post-1';
const kBudSourceMessageId = 'msg-1';

const kBudContext = BeaconCreationContextPromotedChild(
  parentBeaconId: kBudPostId,
  sourceMessageId: kBudSourceMessageId,
);

PostBudInviteCandidate budCandidate(
  String userId, {
  bool hasWritten = false,
  bool pretick = false,
  PostBudInviteOutcome outcome = PostBudInviteOutcome.invited,
  String? viaUserId,
}) => PostBudInviteCandidate(
  userId: userId,
  warm: hasWritten,
  outcome: outcome,
  pretick: pretick,
  hasWritten: hasWritten,
  viaUserId: viaUserId,
);

final class BudCall {
  const BudCall({
    required this.clientCommandId,
    required this.title,
    required this.description,
    required this.isDiscoverable,
    required this.invitees,
    required this.closePost,
    required this.needs,
  });

  final String clientCommandId;
  final String title;
  final String? description;
  final bool isDiscoverable;
  final List<PostBudInvitee> invitees;
  final bool closePost;
  final String? needs;
}

class FakePostBudPort implements PostBudPort {
  List<PostBudInviteCandidate> candidates = const [];

  final calls = <BudCall>[];

  Exception? budError;

  /// When set, `inviteCandidates` waits for it before answering.
  Completer<void>? candidatesGate;

  /// When set, `inviteCandidates` throws it.
  Exception? candidatesError;

  /// When set, `budFromPost` waits for it before answering.
  Completer<void>? gate;

  PostBudResult result = const PostBudResult(
    outcome: PostBudOutcome.created,
    childBeaconId: 'child-1',
  );

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
  }) async {
    await candidatesGate?.future;
    final error = candidatesError;
    if (error != null) throw error;
    return candidates;
  }

  @override
  Future<PostBudResult> budFromPost({
    required String postId,
    required String clientCommandId,
    required String title,
    String? sourceMessageId,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool isDiscoverable = false,
    List<PostBudInvitee> invitees = const [],
    bool closePost = false,
  }) async {
    calls.add(
      BudCall(
        clientCommandId: clientCommandId,
        title: title,
        description: description,
        isDiscoverable: isDiscoverable,
        invitees: invitees,
        closePost: closePost,
        needs: needs,
      ),
    );
    await gate?.future;
    final error = budError;
    if (error != null) throw error;
    return result;
  }
}

class FakeBudProfiles extends Mock implements ProfileRepositoryPort {
  FakeBudProfiles([this.profiles = const []]);

  final List<Profile> profiles;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final p in profiles)
      if (ids.contains(p.id)) p,
  ];
}

/// The Post the bud starts from; by default the budder (`me`) started it,
/// so they may close it (#666).
Beacon budPost({
  BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
  String authorId = 'me',
}) => Beacon.empty.copyWith(
  id: kBudPostId,
  kind: BeaconKind.post,
  forwardPolicy: forwardPolicy,
  author: Profile(id: authorId),
);

/// Everything a bud-mode [BeaconCreateCubit] reads, with fakes.
final class BudHarness {
  BudHarness({
    String sourceText = 'Need a ladder\nFor Saturday at noon.',
    Beacon? parent,
    List<Profile> profiles = const [],
  }) : write = FakeBeaconWritePort(beacon: parent ?? budPost()),
       hierarchy = FakeBeaconHierarchyRepositoryPort(
         promotionSource: BeaconPromotionSource(
           sourceBeaconId: kBudPostId,
           sourceMessageId: kBudSourceMessageId,
           textPreview: sourceText,
           author: const BeaconHierarchyOwnerSummary(
             id: 'me',
             displayName: 'Me',
           ),
         ),
       ),
       profiles = FakeBudProfiles(profiles);

  final FakeBeaconWritePort write;
  final FakeBeaconHierarchyRepositoryPort hierarchy;
  final FakeBudProfiles profiles;
  final port = FakePostBudPort();

  BeaconCreateCase get createCase =>
      BeaconCreateCase(write, FakeBeaconImagePort());

  PostBudCase get postBudCase => PostBudCase(
    port,
    profiles,
    env: const Env(),
    logger: Logger('post-bud-test'),
  );

  MessagePrefillCase get prefillCase => MessagePrefillCase(hierarchy);

  BeaconCreateCubit cubit({
    required UiEffectPort effects,
    bool enabled = true,
  }) => BeaconCreateCubit(
    beaconCreateCase: createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      hierarchy,
      createCase: createCase,
      beacons: write,
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
    messagePrefillCase: prefillCase,
    postBudCase: postBudCase,
    postBuddingEnabled: enabled,
    childCreationContext: kBudContext,
    effects: effects,
  );
}
