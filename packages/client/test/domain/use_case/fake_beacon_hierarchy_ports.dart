import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/domain/port/beacon_child_command_store_port.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

class FakeBeaconHierarchyRepositoryPort implements BeaconHierarchyRepositoryPort {
  FakeBeaconHierarchyRepositoryPort({
    this.promotionSource = const BeaconPromotionSource(
      sourceBeaconId: 'parent-1',
      sourceMessageId: 'msg-1',
      textPreview: 'Promoted text',
      author: BeaconHierarchyOwnerSummary(
        id: 'author-1',
        displayName: 'Alice',
      ),
    ),
  });

  final createCalls = <Map<String, Object?>>[];
  final BeaconPromotionSource promotionSource;

  Object? createError;
  int createAttempts = 0;
  BeaconChildCreateOutcome? createOutcomeOverride;

  String? lastClientCommandId;

  @override
  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  }) async =>
      const BeaconHierarchyCapabilities(canListChildren: true, canCreateChild: true);

  @override
  Future<BeaconHierarchyPage> fetchChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  }) async =>
      const BeaconHierarchyPage(summaries: []);

  @override
  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  }) async =>
      const BeaconParentReference(state: BeaconParentReferenceState.none);

  @override
  Future<BeaconPromotionSource> fetchPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
  }) async =>
      promotionSource;

  @override
  Future<BeaconChildCreateOutcome> createChild({
    required String parentBeaconId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool draft = false,
  }) async {
    createAttempts++;
    lastClientCommandId = clientCommandId;
    createCalls.add({
      'parentBeaconId': parentBeaconId,
      'sourceMessageId': sourceMessageId,
      'clientCommandId': clientCommandId,
      'title': title,
      'description': description,
      'draft': draft,
    });
    if (createError != null) {
      throw createError!;
    }
    if (createOutcomeOverride != null) {
      return createOutcomeOverride!;
    }
    return BeaconChildCreateOutcome(
      outcome: createAttempts == 1
          ? BeaconChildCommandOutcome.created
          : BeaconChildCommandOutcome.replayed,
      beaconId: 'child-$clientCommandId',
    );
  }
}

class InMemoryBeaconChildCommandStore implements BeaconChildCommandStorePort {
  final _values = <String, String>{};

  static String _key(BeaconCreationContext context) => switch (context) {
    BeaconCreationContextChild(:final parentBeaconId) => 'child:$parentBeaconId',
    BeaconCreationContextPromotedChild(
      :final parentBeaconId,
      :final sourceMessageId,
    ) =>
      'promo:$parentBeaconId:$sourceMessageId',
    BeaconCreationContextStandalone() => throw ArgumentError('standalone'),
  };

  @override
  Future<void> clear(BeaconCreationContext context) async {
    _values.remove(_key(context));
  }

  @override
  Future<String?> read(BeaconCreationContext context) async =>
      _values[_key(context)];

  @override
  Future<void> write(
    BeaconCreationContext context,
    String clientCommandId,
  ) async {
    _values[_key(context)] = clientCommandId;
  }
}
