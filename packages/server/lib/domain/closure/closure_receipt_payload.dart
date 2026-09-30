import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';

/// Receipt payloads carry codes only (strings), never numbers (Arch §7, §9).

Map<String, Object?> closureOpenedReceiptPayload() => const {};

Map<String, Object?> closureCancelledReceiptPayload() => const {};

Map<String, Object?> closureFinalizedReceiptPayload({
  required ClosureOutcome outcome,
  required ClosureBand band,
  required ClosureResultDraftFlag draftFlag,
}) => {
  'outcome': outcome.name,
  'band': band.name,
  'draftFlag': draftFlag.name,
};
