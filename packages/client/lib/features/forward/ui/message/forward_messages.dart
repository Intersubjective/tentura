import 'dart:async' show unawaited;

import 'package:get_it/get_it.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/message/action_message_base.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

String _forwardLocationPauseSuffixEn({
  String? skippedName,
  int? skippedCount,
}) {
  if (skippedName != null) {
    return ' — $skippedName isn\'t taking new requests right now.';
  }
  if (skippedCount != null) {
    return ' — $skippedCount people aren\'t taking new requests right now.';
  }
  return '';
}

String _forwardLocationPauseSuffixRu({
  String? skippedName,
  int? skippedCount,
}) {
  if (skippedName != null) {
    return ' — $skippedName сейчас не принимает новые запросы.';
  }
  if (skippedCount != null) {
    return ' — $skippedCount получателей сейчас не принимают новые запросы.';
  }
  return '';
}

String forwardLocationCopyEn({
  required bool inWatching,
  String? skippedName,
  int? skippedCount,
}) {
  final base = inWatching
      ? 'Request forwarded. It\'s in Watching.'
      : 'Request forwarded. It\'s in My Work.';
  return '$base${_forwardLocationPauseSuffixEn(skippedName: skippedName, skippedCount: skippedCount)}';
}

String forwardLocationCopyRu({
  required bool inWatching,
  String? skippedName,
  int? skippedCount,
}) {
  final base = inWatching
      ? 'Запрос переслан. Он во вкладке «Наблюдаю».'
      : 'Запрос переслан. Он в «Моей работе».';
  return '$base${_forwardLocationPauseSuffixRu(skippedName: skippedName, skippedCount: skippedCount)}';
}

final class ForwardSentMessage extends LocalizableMessage {
  const ForwardSentMessage(this.count);

  final int count;

  @override
  String get toEn => count == 1
      ? 'Request forwarded to 1 person'
      : 'Request forwarded to $count people';

  @override
  String get toRu => count == 1
      ? 'Запрос переслан: 1 человеку'
      : 'Запрос переслан: $count людям';
}

/// Partial or zero delivery when one person was skipped for availability.
final class ForwardPartialDeliveryMessage extends LocalizableMessage {
  const ForwardPartialDeliveryMessage({
    required this.deliveredCount,
    required this.requestedCount,
    required this.skippedName,
  });

  final int deliveredCount;
  final int requestedCount;
  final String skippedName;

  @override
  String get toEn =>
      'Delivered to $deliveredCount of $requestedCount — $skippedName isn\'t taking new requests right now.';

  @override
  String get toRu =>
      'Отправлено $deliveredCount из $requestedCount — $skippedName сейчас не принимает новые запросы.';
}

/// Partial or zero delivery when two or more people were skipped for availability.
final class ForwardPartialDeliveryManyMessage extends LocalizableMessage {
  const ForwardPartialDeliveryManyMessage({
    required this.deliveredCount,
    required this.requestedCount,
    required this.skippedCount,
  });

  final int deliveredCount;
  final int requestedCount;
  final int skippedCount;

  @override
  String get toEn =>
      'Delivered to $deliveredCount of $requestedCount — $skippedCount people aren\'t taking new requests right now.';

  @override
  String get toRu =>
      'Отправлено $deliveredCount из $requestedCount — $skippedCount получателей сейчас не принимают новые запросы.';
}

/// Standalone forward success: ego home is Inbox Watching (not author, no help offer).
final class ForwardLocationMessage extends LocalizableActionMessage {
  const ForwardLocationMessage({
    required this.beaconId,
    this.skippedName,
    this.skippedCount,
  });

  final String beaconId;
  final String? skippedName;
  final int? skippedCount;

  @override
  String get toEn => forwardLocationCopyEn(
    inWatching: true,
    skippedName: skippedName,
    skippedCount: skippedCount,
  );

  @override
  String get toRu => forwardLocationCopyRu(
    inWatching: true,
    skippedName: skippedName,
    skippedCount: skippedCount,
  );

  @override
  LocalizableMessage get label => const _OpenInWatchingLabel();

  @override
  void Function() get onPressed => () {
    GetIt.I<HomeTabReselectCubit>().requestInboxWatching(beaconId);
    unawaited(
      GetIt.I<RootRouter>().replaceAll([
        HomeRoute(children: [inboxTabShell(children: [const InboxRoute()])]),
      ]),
    );
  };
}

/// Standalone forward success: ego home is My Work (author or active help offer).
final class ForwardLocationMyWorkMessage extends LocalizableMessage {
  const ForwardLocationMyWorkMessage({
    this.skippedName,
    this.skippedCount,
  });

  final String? skippedName;
  final int? skippedCount;

  @override
  String get toEn => forwardLocationCopyEn(
    inWatching: false,
    skippedName: skippedName,
    skippedCount: skippedCount,
  );

  @override
  String get toRu => forwardLocationCopyRu(
    inWatching: false,
    skippedName: skippedName,
    skippedCount: skippedCount,
  );
}

final class _OpenInWatchingLabel extends LocalizableMessage {
  const _OpenInWatchingLabel();

  @override
  String get toEn => 'Open in Watching';

  @override
  String get toRu => 'Открыть в «Наблюдаю»';
}

/// Embedded beacon-create confirmation: delivered count against requested denominator.
final class ForwardDeliveredOfMessage extends LocalizableMessage {
  const ForwardDeliveredOfMessage({
    required this.deliveredCount,
    required this.requestedCount,
  });

  final int deliveredCount;
  final int requestedCount;

  @override
  String get toEn {
    if (deliveredCount == 1 && requestedCount == 1) {
      return 'Delivered to 1 of 1 person';
    }
    return 'Delivered to $deliveredCount of $requestedCount people';
  }

  @override
  String get toRu {
    if (deliveredCount == 1 && requestedCount == 1) {
      return 'Доставлено 1 из 1 человека';
    }
    return 'Доставлено $deliveredCount из $requestedCount людей';
  }
}
