import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AppendItemMessageCase extends UseCaseBase {
  AppendItemMessageCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItemMessage> call({
    required String userId,
    required String itemId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Message body is required');
    }
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Item not found');
    }
    return _itemRepository.appendMessage(
      itemId: itemId,
      senderId: userId,
      body: trimmed,
    );
  }
}
