import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';

import '../../support/recording_commitment_repository.dart';
import 'evaluation_graph_test_repos.dart';

void main() {
  const beaconId = 'B-test';
  const authorId = 'author';
  const helperId = 'helper1';
  const forwarderId = 'forwarder1';
  final offerCreatedAt = DateTime.utc(2025, 3, 15);

  late EvaluationParticipantGraphBuilder builder;

  group('EvaluationParticipantGraphBuilder', () {
    test(
      'active acknowledged helper remains committer',
      () async {
        final offer = HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: offerCreatedAt,
          updatedAt: offerCreatedAt,
          message: 'I can help',
        );
        builder = EvaluationParticipantGraphBuilder(
          acknowledgedCommitterCommitmentRepo(
            beaconId: beaconId,
            helperId: helperId,
            authorId: authorId,
          ),
          ConfigurableGraphHelpOfferRepository([offer]),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );

        final graph = await builder.build(
          beaconId: beaconId,
          authorId: authorId,
          preClosure: false,
        );

        final helper = graph.participants.singleWhere((p) => p.userId == helperId);
        expect(helper.role, EvaluationParticipantRole.committer);
        expect(helper.contributionSummary, contains('I can help'));
        expect(helper.contributionSummary, isNot(contains('participation ended')));
      },
    );

    test(
      'helper who withdrew after grace appears as formerCommitter',
      () async {
        final offer = HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: offerCreatedAt,
          updatedAt: offerCreatedAt.add(const Duration(hours: 31)),
          status: 1,
          message: 'helped out',
        );
        builder = EvaluationParticipantGraphBuilder(
          acknowledgedCommitterCommitmentRepo(
            beaconId: beaconId,
            helperId: helperId,
            authorId: authorId,
            withdrawAfterAck: const Duration(hours: 30),
          ),
          ConfigurableGraphHelpOfferRepository([offer]),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );

        final graph = await builder.build(
          beaconId: beaconId,
          authorId: authorId,
          preClosure: false,
        );

        final helper = graph.participants.singleWhere((p) => p.userId == helperId);
        expect(helper.role, EvaluationParticipantRole.formerCommitter);
      },
    );

    test(
      'helper who withdrew within grace is absent from composition',
      () async {
        final offer = HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: offerCreatedAt,
          updatedAt: offerCreatedAt.add(const Duration(hours: 2)),
          status: 1,
        );
        builder = EvaluationParticipantGraphBuilder(
          acknowledgedCommitterCommitmentRepo(
            beaconId: beaconId,
            helperId: helperId,
            authorId: authorId,
            withdrawAfterAck: const Duration(hours: 1),
          ),
          ConfigurableGraphHelpOfferRepository([offer]),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );

        final graph = await builder.build(
          beaconId: beaconId,
          authorId: authorId,
          preClosure: false,
        );

        expect(
          graph.participants.where((p) => p.userId == helperId),
          isEmpty,
        );
      },
    );

    test(
      'former committer summary and hint end with participation ended marker',
      () async {
        final offer = HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: offerCreatedAt,
          updatedAt: offerCreatedAt,
          status: 1,
        );
        builder = EvaluationParticipantGraphBuilder(
          acknowledgedCommitterCommitmentRepo(
            beaconId: beaconId,
            helperId: helperId,
            authorId: authorId,
            withdrawAfterAck: const Duration(hours: 30),
          ),
          ConfigurableGraphHelpOfferRepository([offer]),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );

        final graph = await builder.build(
          beaconId: beaconId,
          authorId: authorId,
          preClosure: false,
        );

        final helper = graph.participants.singleWhere((p) => p.userId == helperId);
        expect(helper.contributionSummary, endsWith(' — participation ended'));
        expect(helper.causalHint, endsWith(' — participation ended'));
      },
    );

    test(
      'forwarders are included when recipient is a former committer',
      () async {
        final offer = HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: offerCreatedAt,
          updatedAt: offerCreatedAt,
          status: 1,
        );
        final edge = ForwardEdgeEntity(
          id: 'F1',
          beaconId: beaconId,
          senderId: forwarderId,
          recipientId: helperId,
          createdAt: offerCreatedAt,
        );
        builder = EvaluationParticipantGraphBuilder(
          acknowledgedCommitterCommitmentRepo(
            beaconId: beaconId,
            helperId: helperId,
            authorId: authorId,
            withdrawAfterAck: const Duration(hours: 30),
          ),
          ConfigurableGraphHelpOfferRepository([offer]),
          ConfigurableGraphForwardEdgeRepository([edge]),
          StubUserRepository('Helper'),
        );

        final graph = await builder.build(
          beaconId: beaconId,
          authorId: authorId,
          preClosure: false,
        );

        expect(
          graph.participants.any(
            (p) =>
                p.userId == forwarderId &&
                p.role == EvaluationParticipantRole.forwarder,
          ),
          isTrue,
        );
        expect(graph.latestEdgeToCommitter[helperId], edge);
      },
    );
  });
}
