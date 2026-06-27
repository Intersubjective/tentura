import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/complaint_entity.dart';
import 'package:tentura_server/domain/port/complaint_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class ComplaintCase extends UseCaseBase {
  ComplaintCase(
    this._complaintRepository,
    this._emailSender, {
    required super.env,
    required super.logger,
  });

  final ComplaintRepositoryPort _complaintRepository;
  final EmailSenderPort _emailSender;

  Future<bool> create({
    required String id,
    required String type,
    required String email,
    required String userId,
    required String details,
  }) async {
    try {
      final complaintType = ComplaintType.values.firstWhere(
        (e) => e.name == type,
        orElse: () => ComplaintType.unknown,
      );
      final entity = ComplaintEntity(
        id: id,
        type: complaintType,
        email: email,
        userId: userId,
        details: details,
        createdAt: DateTime.timestamp(),
      );
      await _complaintRepository.create(entity);
      if (complaintType == ComplaintType.accountDeletionRequest) {
        await _notifyAccountDeletionRequest(email: email, entity: entity);
      }
      return true;
    } catch (e, st) {
      logger.severe('complaint create failed', e, st);
      rethrow;
    }
  }

  Future<void> _notifyAccountDeletionRequest({
    required String email,
    required ComplaintEntity entity,
  }) async {
    final payload = AccountDeletionRequestEmailPayload(
      complaintId: entity.id,
      userId: entity.userId,
      contactEmail: email,
      details: entity.details,
      requestedAt: entity.createdAt,
    );

    if (env.complaintEmail.isNotEmpty && env.isEmailAuthConfigured) {
      try {
        await _emailSender.sendAccountDeletionRequestAdminEmail(
          to: env.complaintEmail,
          payload: payload,
        );
      } catch (e, st) {
        logger.severe('account deletion admin email failed', e, st);
      }
    } else {
      logger.warning('account deletion admin email skipped: not configured');
    }

    final normalized = normalizeAuthEmail(email);
    if (env.isEmailAuthConfigured && isValidAuthEmailFormat(normalized)) {
      try {
        await _emailSender.sendAccountDeletionRequestUserConfirmation(
          to: normalized,
          payload: payload,
        );
      } catch (e, st) {
        logger.severe('account deletion user confirmation failed', e, st);
      }
    } else {
      logger.warning('account deletion user confirmation skipped');
    }
  }
}
