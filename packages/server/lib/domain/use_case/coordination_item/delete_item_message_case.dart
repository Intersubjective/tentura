import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class DeleteItemMessageCase extends UseCaseBase {
  DeleteItemMessageCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

  Future<bool> call({
    required String userId,
    required String itemId,
    required String messageId,
  }) async {
    final msg = await _itemRepository.getMessageById(messageId);
    if (msg == null || msg.itemId != itemId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Item message not found',
      );
    }
    if (msg.senderId != userId) {
      throw const UnauthorizedException(
        description: 'Only the message sender can delete messages',
      );
    }
    await _itemRepository.deleteMessage(messageId: messageId);
    return true;
  }
}
