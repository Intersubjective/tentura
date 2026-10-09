import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:test/test.dart';

/// Repository whose batch path resolves profiles from [db] directly, so pg
/// tests need no service locator.
ConstellationAnchorRepository constellationAnchorRepositoryFor(TenturaDb db) =>
    ConstellationAnchorRepository(
      db,
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
    );

/// Seeds anchors through the retained batch protocol while keeping storage and
/// concurrency fixtures focused on their authoritative row/cursor assertions.
extension ConstellationAnchorBatchFixture on ConstellationAnchorRepositoryPort {
  Future<({ConstellationAnchor anchor, ConstellationAnchorWatermark watermark})>
  applyAnchorUpsert({
    required String viewerId,
    required String context,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    final result = await applyBatch(
      viewerId: viewerId,
      ops: [
        AnchorApplyOp(
          clientOpId: generateId('CAOP'),
          kind: AnchorOpKind.upsert,
          target: target,
          position: position,
        ),
      ],
      params: AnchorApplyParams(
        context: context,
        filters: ConstellationFieldMembershipFilters.defaults,
      ),
    );
    expect(
      result.results.single.status,
      AnchorOpStatus.ok,
      reason: result.results.single.reason,
    );
    return (
      anchor: result.projection.anchors.singleWhere((a) => a.target == target),
      watermark: ConstellationAnchorWatermark(result.afterRevision),
    );
  }

  Future<
    ({ConstellationAnchorTarget target, ConstellationAnchorWatermark watermark})
  >
  applyAnchorDelete({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) async {
    final result = await applyBatch(
      viewerId: viewerId,
      ops: [
        AnchorApplyOp(
          clientOpId: generateId('CAOP'),
          kind: AnchorOpKind.delete,
          target: target,
        ),
      ],
      params: const AnchorApplyParams(
        context: kConstellationContext,
        filters: ConstellationFieldMembershipFilters.defaults,
      ),
    );
    expect(
      result.results.single.status,
      AnchorOpStatus.ok,
      reason: result.results.single.reason,
    );
    return (
      target: target,
      watermark: ConstellationAnchorWatermark(result.afterRevision),
    );
  }
}
