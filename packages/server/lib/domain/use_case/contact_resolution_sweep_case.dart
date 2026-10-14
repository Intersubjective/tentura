import 'dart:math';

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
/// Each chunk's claim, resolve-as-ignored, evidence write and projection share
/// one bounded transaction, so a failed chunk is retried whole. A run loops
/// chunk by chunk until the backlog is empty or its row/time budget is spent.
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
    final batchSize = env.contactResolutionBatchSize;
    final rowBudget = env.contactResolutionRunRowBudget;
    final timeBudget = env.contactResolutionRunTimeBudget;
    final stopwatch = Stopwatch()..start();
    var processed = 0;
    try {
      while (processed < rowBudget && stopwatch.elapsed < timeBudget) {
        final limit = min(batchSize, rowBudget - processed);
        final claimed = await _uow.run<int>(
          action: () async {
            final ignored = await _forwardEdges.claimIgnoredContacts(
              limit: limit,
            );
            if (ignored.isEmpty) return 0;
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
            return ignored.length;
          },
        );
        processed += claimed;
        if (claimed < limit) break;
      }
    } catch (e, s) {
      logger.severe('contact resolution sweep failed', e, s);
    }
  }
}
