import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/message/action_message_base.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

Future<void> runBeaconDeleteWithRetry(
  BuildContext context, {
  required Future<void> Function() delete,
}) async {
  try {
    await delete();
  } catch (_) {
    if (!context.mounted) return;
    final l10n = L10n.of(context)!;
    showSnackBar(
      context,
      isError: true,
      text: l10n.beaconDeleteFailedRetry,
      action: SnackBarAction(
        label: l10n.myWorkRetry,
        onPressed: () => unawaited(
          runBeaconDeleteWithRetry(context, delete: delete),
        ),
      ),
    );
  }
}

final class BeaconDeleteFailedMessage extends LocalizableActionMessage {
  const BeaconDeleteFailedMessage(this.onRetry);

  final void Function() onRetry;

  @override
  String get toEn => "Couldn't delete the request";

  @override
  String get toRu => 'Не удалось удалить запрос';

  @override
  LocalizableMessage get label => const _DeleteRetryLabel();

  @override
  void Function() get onPressed => onRetry;
}

final class _DeleteRetryLabel extends LocalizableMessage {
  const _DeleteRetryLabel();

  @override
  String get toEn => 'Try again';

  @override
  String get toRu => 'Повторить';
}
