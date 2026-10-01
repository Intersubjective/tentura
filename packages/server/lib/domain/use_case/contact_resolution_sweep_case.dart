import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import '_use_case_base.dart';

/// B2: forwards still unanswered after their deadline become `noisy`
/// recipient→sender evidence (Arch §6). Runs hourly.
///
/// Claim, resolve-as-ignored and evidence write share one transaction, so a
/// failed batch is retried whole and a second run finds nothing to claim.
@Singleton(order: 3)
final class ContactResolutionSweepCase extends UseCaseBase {
  ContactResolutionSweepCase({
    required MutatingUnitOfWorkPort unitOfWork,
    required ForwardEdgeRepositoryPort forwardEdgeRepository,
    required TrustLedgerPort trustLedger,
    required super.env,
    required super.logger,
  }) : _uow = unitOfWork,
       _forwardEdges = forwardEdgeRepository,
       _ledger = trustLedger;

  final MutatingUnitOfWorkPort _uow;
  final ForwardEdgeRepositoryPort _forwardEdges;
  final TrustLedgerPort _ledger;

  Future<void> run() async {
    try {
      await _uow.run<void>(
        action: () async {
          final ignored = await _forwardEdges.claimIgnoredContacts();
          if (ignored.isEmpty) return;
          await _ledger.record([
            for (final c in ignored)
              LedgerEvidence(
                subjectId: c.recipientId,
                objectId: c.senderId,
                kind: TrustEvidenceKind.noisy,
                count: 1,
                sourceKey: 'contact:${c.edgeId}:noisy',
                beaconId: c.beaconId,
              ),
          ]);
        },
      );
    } catch (e, s) {
      logger.severe('contact resolution sweep failed', e, s);
    }
  }
}
