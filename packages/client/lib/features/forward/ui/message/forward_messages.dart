import 'dart:async' show unawaited;

import 'package:flutter/material.dart' show Dialog, Navigator, showDialog;
import 'package:get_it/get_it.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_suggestion_card.dart';
import 'package:tentura/ui/message/action_message_base.dart';

/// « — who was skipped, and why.» after a forward line, or '' when nobody
/// was skipped. One person per reason is named; more are counted. A pause
/// is [skippedName] / [skippedCount].
String _forwardSkipSuffixEn({
  String? skippedName,
  int? skippedCount,
  List<String> alreadyForwardedNames = const [],
  List<String> blockedNames = const [],
}) {
  final parts = [
    if (skippedName != null)
      "$skippedName isn't taking new requests right now"
    else if (skippedCount != null)
      "$skippedCount people aren't taking new requests right now",
    if (alreadyForwardedNames.length == 1)
      'you already sent it to ${alreadyForwardedNames.single}'
    else if (alreadyForwardedNames.length > 1)
      'you already sent it to ${alreadyForwardedNames.length} people',
    if (blockedNames.length == 1)
      "${blockedNames.single} can't receive it from you"
    else if (blockedNames.length > 1)
      "${blockedNames.length} people can't receive it from you",
  ];
  return parts.isEmpty ? '' : ' — ${parts.join('; ')}.';
}

String _forwardSkipSuffixRu({
  String? skippedName,
  int? skippedCount,
  List<String> alreadyForwardedNames = const [],
  List<String> blockedNames = const [],
}) {
  final parts = [
    if (skippedName != null)
      '$skippedName сейчас не принимает новые запросы'
    else if (skippedCount != null)
      '$skippedCount получателей сейчас не принимают новые запросы',
    if (alreadyForwardedNames.length == 1)
      'вы уже отправили его: ${alreadyForwardedNames.single}'
    else if (alreadyForwardedNames.length > 1)
      'вы уже отправили его ${alreadyForwardedNames.length} получателям',
    if (blockedNames.length == 1)
      '${blockedNames.single} не может получить его от вас'
    else if (blockedNames.length > 1)
      '${blockedNames.length} получателей не могут получить его от вас',
  ];
  return parts.isEmpty ? '' : ' — ${parts.join('; ')}.';
}

String forwardLocationCopyEn({
  required bool inWatching,
  String? skippedName,
  int? skippedCount,
  List<String> alreadyForwardedNames = const [],
  List<String> blockedNames = const [],
}) {
  final base = inWatching
      ? "Request forwarded. It's in Following."
      : "Request forwarded. It's in My Work.";
  return '$base${_forwardSkipSuffixEn(skippedName: skippedName, skippedCount: skippedCount, alreadyForwardedNames: alreadyForwardedNames, blockedNames: blockedNames)}';
}

String forwardLocationCopyRu({
  required bool inWatching,
  String? skippedName,
  int? skippedCount,
  List<String> alreadyForwardedNames = const [],
  List<String> blockedNames = const [],
}) {
  final base = inWatching
      ? 'Запрос переслан. Он во вкладке «Слежу».'
      : 'Запрос переслан. Он в «Моей работе».';
  return '$base${_forwardSkipSuffixRu(skippedName: skippedName, skippedCount: skippedCount, alreadyForwardedNames: alreadyForwardedNames, blockedNames: blockedNames)}';
}

/// Standalone forward of a Post (#501): a Post is not a request and has no
/// Following / My Work home, so the line names the Post and stops there.
final class ForwardPostSentMessage extends LocalizableMessage {
  const ForwardPostSentMessage({
    this.skippedName,
    this.skippedCount,
    this.alreadyForwardedNames = const [],
    this.blockedNames = const [],
  });

  final String? skippedName;
  final int? skippedCount;
  final List<String> alreadyForwardedNames;
  final List<String> blockedNames;

  @override
  String get toEn =>
      'Post forwarded.${_forwardSkipSuffixEn(skippedName: skippedName, skippedCount: skippedCount, alreadyForwardedNames: alreadyForwardedNames, blockedNames: blockedNames)}';

  @override
  String get toRu =>
      'Пост переслан.${_forwardSkipSuffixRu(skippedName: skippedName, skippedCount: skippedCount, alreadyForwardedNames: alreadyForwardedNames, blockedNames: blockedNames)}';
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
      "Delivered to $deliveredCount of $requestedCount — $skippedName isn't taking new requests right now.";

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
      "Delivered to $deliveredCount of $requestedCount — $skippedCount people aren't taking new requests right now.";

  @override
  String get toRu =>
      'Отправлено $deliveredCount из $requestedCount — $skippedCount получателей сейчас не принимают новые запросы.';
}

/// Nobody received the forward and at least one recipient was skipped as
/// already forwarded or blocked, or the server gave no reason at all.
final class ForwardNotDeliveredMessage extends LocalizableMessage {
  const ForwardNotDeliveredMessage({
    this.skippedName,
    this.skippedCount,
    this.alreadyForwardedNames = const [],
    this.blockedNames = const [],
  });

  final String? skippedName;
  final int? skippedCount;
  final List<String> alreadyForwardedNames;
  final List<String> blockedNames;

  @override
  String get toEn {
    final why = _forwardSkipSuffixEn(
      skippedName: skippedName,
      skippedCount: skippedCount,
      alreadyForwardedNames: alreadyForwardedNames,
      blockedNames: blockedNames,
    );
    return why.isEmpty
        ? 'Not delivered to anyone. Try again later.'
        : 'Not delivered$why';
  }

  @override
  String get toRu {
    final why = _forwardSkipSuffixRu(
      skippedName: skippedName,
      skippedCount: skippedCount,
      alreadyForwardedNames: alreadyForwardedNames,
      blockedNames: blockedNames,
    );
    return why.isEmpty
        ? 'Никому не доставлено. Попробуйте позже.'
        : 'Не доставлено$why';
  }
}

/// Standalone forward success: ego home is Inbox Watching (not author, no help offer).
final class ForwardLocationMessage extends LocalizableActionMessage {
  const ForwardLocationMessage({
    required this.beaconId,
    this.skippedName,
    this.skippedCount,
    this.alreadyForwardedNames = const [],
    this.blockedNames = const [],
  });

  final String beaconId;
  final String? skippedName;
  final int? skippedCount;
  final List<String> alreadyForwardedNames;
  final List<String> blockedNames;

  @override
  String get toEn => forwardLocationCopyEn(
    inWatching: true,
    skippedName: skippedName,
    skippedCount: skippedCount,
    alreadyForwardedNames: alreadyForwardedNames,
    blockedNames: blockedNames,
  );

  @override
  String get toRu => forwardLocationCopyRu(
    inWatching: true,
    skippedName: skippedName,
    skippedCount: skippedCount,
    alreadyForwardedNames: alreadyForwardedNames,
    blockedNames: blockedNames,
  );

  @override
  LocalizableMessage get label => const _OpenInWatchingLabel();

  @override
  void Function() get onPressed => () {
    unawaited(_openForwardedRequestInWatching(beaconId));
  };
}

Future<void> _openForwardedRequestInWatching(String beaconId) async {
  final router = GetIt.I<RootRouter>();
  await router.replaceAll([
    HomeRoute(
      children: [
        inboxTabShell(children: [InboxRoute()]),
      ],
    ),
  ]);
  await router.push(
    InboxWatchingRoute(highlightBeaconId: beaconId),
  );
}

/// Standalone forward success: ego home is My Work (author or active help offer).
base class ForwardLocationMyWorkMessage extends LocalizableMessage {
  const ForwardLocationMyWorkMessage({
    this.skippedName,
    this.skippedCount,
    this.alreadyForwardedNames = const [],
    this.blockedNames = const [],
  });

  final String? skippedName;
  final int? skippedCount;
  final List<String> alreadyForwardedNames;
  final List<String> blockedNames;

  @override
  String get toEn => forwardLocationCopyEn(
    inWatching: false,
    skippedName: skippedName,
    skippedCount: skippedCount,
    alreadyForwardedNames: alreadyForwardedNames,
    blockedNames: blockedNames,
  );

  @override
  String get toRu => forwardLocationCopyRu(
    inWatching: false,
    skippedName: skippedName,
    skippedCount: skippedCount,
    alreadyForwardedNames: alreadyForwardedNames,
    blockedNames: blockedNames,
  );
}

/// [ForwardLocationMyWorkMessage] to two or more people, with an
/// "Add to tag…" action that offers them the private "Tag them?" card.
final class ForwardLocationMyWorkAddToTagMessage
    extends ForwardLocationMyWorkMessage
    implements LocalizableActionMessage {
  const ForwardLocationMyWorkAddToTagMessage({
    required this.beaconId,
    required this.recipientIds,
    required this.recipientNames,
    super.skippedName,
    super.skippedCount,
    super.alreadyForwardedNames,
    super.blockedNames,
  });

  final String beaconId;
  final List<String> recipientIds;
  final String recipientNames;

  @override
  LocalizableMessage get label => const _AddToTagLabel();

  @override
  void Function() get onPressed => () async {
    final event = PeopleTagSuggestionEvent.forwardSent(
      '$beaconId:${([...recipientIds]..sort()).join(',')}',
    );
    try {
      if (!await GetIt.I<PeopleTagSuggestionCase>().shouldShow(event)) return;
    } catch (_) {
      return;
    }
    final context = GetIt.I<RootRouter>().navigatorKey.currentContext;
    if (context == null) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: TagSuggestionCard(
            event: event,
            personIds: recipientIds,
            names: recipientNames,
            alreadyEligible: true,
            onDismissed: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  };
}

final class _AddToTagLabel extends LocalizableMessage {
  const _AddToTagLabel();

  @override
  String get toEn => 'Add to tag…';

  @override
  String get toRu => 'В тег…';
}

final class _OpenInWatchingLabel extends LocalizableMessage {
  const _OpenInWatchingLabel();

  @override
  String get toEn => 'Open in Following';

  @override
  String get toRu => 'Открыть в «Слежу»';
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
