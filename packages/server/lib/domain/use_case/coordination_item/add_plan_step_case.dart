import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AddPlanStepCase extends UseCaseBase {
  AddPlanStepCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItem> call({
    required String userId,
    required String parentItemId,
    required String title,
    String body = '',
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Step title is required');
    }
    final parent = await _itemRepository.getById(parentItemId);
    if (parent == null) {
      throw const BeaconCreateException(description: 'Plan not found');
    }
    if (parent.kind != coordinationItemKindPlan) {
      throw const BeaconCreateException(description: 'Parent is not a plan');
    }
    return _itemRepository.addPlanStep(
      parentItemId: parentItemId,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
    );
  }
}
