import 'package:tentura_server/consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_excerpt.dart';

class BeaconNotificationCopy {
  const BeaconNotificationCopy({
    required this.title,
    required this.body,
    required this.actionUrl,
    this.excerpt = '',
  });

  final String title;
  final String body;
  final String actionUrl;

  /// The words [body] quotes, alone — no Request title, no fallback sentence.
  /// Empty when the event carries none.
  final String excerpt;
}

class BeaconNotificationCopyBuilder {
  const BeaconNotificationCopyBuilder();

  BeaconNotificationCopy build({
    required BeaconNotificationIntent intent,
    required String actorDisplayName,
    String locale = 'en',
  }) {
    final ru = locale.toLowerCase().startsWith('ru');
    final isPost = intent.beaconKind == BeaconKind.post;
    final actor = actorDisplayName.isEmpty
        ? (ru ? 'Кто-то' : 'Someone')
        : actorDisplayName;
    final excerpt = notificationExcerpt(
      intent.bodyExcerpt.isNotEmpty ? intent.bodyExcerpt : intent.titleExcerpt,
    );
    final beaconTitle = intent.beaconTitle.trim();
    final itemNoun = _coordinationItemNoun(intent.coordinationItemKind);
    final ruItem = _ruCoordinationItem(intent.coordinationItemKind);

    final (title, body) = switch (intent.kind) {
      NotificationKind.deadlineChanged => (
        ru ? 'Срок изменён' : 'Deadline changed',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Срок запроса изменился'
              : 'The request deadline changed',
        ),
      ),
      NotificationKind.deadlineReminder => (
        ru ? 'Напоминание о сроке' : 'Deadline reminder',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Срок запроса — завтра'
              : 'This request deadline is tomorrow',
        ),
      ),
      NotificationKind.needsMe => (
        ru ? 'Вас просят' : 'Asked of you',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'В обсуждении запроса нужен ваш ответ'
              : 'Action needed in the request discussion',
        ),
      ),
      NotificationKind.promiseMade =>
        intent.promiseWithdrawn
            ? (
                ru ? '$actor отозвал(а) обещание' : '$actor withdrew a promise',
                _bodyWithRequest(
                  beaconTitle: beaconTitle,
                  excerpt: excerpt,
                  fallback: ru ? 'Обещание отозвано' : 'Promise withdrawn',
                ),
              )
            : (
                ru ? '$actor пообещал(а)' : '$actor promised',
                _bodyWithRequest(
                  beaconTitle: beaconTitle,
                  excerpt: excerpt,
                  fallback: ru
                      ? 'Новое обещание в обсуждении запроса'
                      : 'New promise in the request discussion',
                ),
              ),
      NotificationKind.coordinationChanged => (
        ru ? 'План обновлён' : 'Plan updated',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Договорённости изменились' : 'Coordination changed',
        ),
      ),
      NotificationKind.blockerOpened => (
        ru ? 'Появился блокер' : 'Blocker opened',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'В запросе появился блокер' : 'A blocker was opened',
        ),
      ),
      NotificationKind.blockerResolved => (
        ru ? 'Блокер снят' : 'Blocker resolved',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Блокер в запросе снят' : 'A blocker was resolved',
        ),
      ),
      NotificationKind.roomAccess => (
        ru ? '$actor принял(а) ваше предложение' : '$actor accepted your offer',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Ваше предложение принято' : 'Your offer was accepted',
        ),
      ),
      NotificationKind.commitmentDeclined => (
        ru ? 'Предложение отклонено' : 'Offer declined',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Ваше предложение помощи отклонено'
              : 'Your offer was declined',
        ),
      ),
      NotificationKind.commitmentRemoved => (
        ru ? 'Вас убрали из обсуждения' : 'Removed from the discussion',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Вас убрали из обсуждения запроса'
              : 'You were removed from the request discussion',
        ),
      ),
      NotificationKind.commitmentReleased => (
        ru ? 'Участие завершено' : 'Participation ended',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Автор завершил ваше участие в этом запросе'
              : 'The author ended your participation in this request',
        ),
      ),
      NotificationKind.newRelay => (
        actor,
        excerpt.isNotEmpty
            ? '$actor: $excerpt'
            : isPost
            ? (ru
                  ? '$actor поделился постом с вами'
                  : '$actor shared a post with you')
            : ru
            ? '$actor переслал(а) вам запрос'
            : '$actor forwarded a request to you',
      ),
      NotificationKind.commitmentEvent =>
        intent.promiseWithdrawn
            ? (
                actor,
                excerpt.isNotEmpty
                    ? excerpt
                    : ru
                    ? '$actor отозвал(а) свою помощь'
                    : '$actor withdrew their help',
              )
            : intent.isBackupOffer
            ? (
                actor,
                excerpt.isNotEmpty
                    ? excerpt
                    : ru
                    ? '$actor предложил(а) помощь как запасной вариант'
                    : '$actor offered to help as backup',
              )
            : (
                actor,
                excerpt.isNotEmpty
                    ? excerpt
                    : ru
                    ? '$actor предложил(а) помощь'
                    : '$actor offered help',
              ),
      NotificationKind.reviewReady => (
        ru
            ? 'Запрос закрыт — подведите итоги'
            : 'Request closed — close the loop',
        beaconTitle.isNotEmpty
            ? beaconTitle
            : ru
            ? 'Отметьте, чья помощь была важной'
            : 'Review contributions',
      ),
      NotificationKind.roomActivityLowPriority => (
        beaconTitle.isNotEmpty
            ? beaconTitle
            : ru
            ? 'Новое в запросе'
            : 'Request update',
        _bodyWithRequest(
          beaconTitle: '',
          excerpt: excerpt,
          fallback: ru ? 'Новое сообщение в обсуждении' : 'New thread update',
        ),
      ),
      NotificationKind.roomMention => (
        actor,
        excerpt.isNotEmpty
            ? excerpt
            : ru
            ? '$actor упомянул(а) вас'
            : '$actor mentioned you',
      ),
      NotificationKind.postFirstResponse => (
        actor,
        excerpt.isNotEmpty
            ? excerpt
            : ru
            ? '$actor откликнулся на ваш пост'
            : '$actor replied to your post',
      ),
      NotificationKind.batonAsked => (
        ru
            ? '$actor спрашивает, сможете ли вы помочь'
            : '$actor asks you can help',
        excerpt.isNotEmpty
            ? excerpt
            : ru
            ? '$actor спрашивает, сможете ли вы помочь'
            : '$actor asks you can help',
      ),
      NotificationKind.batonTaken => (
        ru ? 'Вы взялись за это' : 'You took it',
        ru ? 'Вы взялись: $excerpt' : 'You took it: $excerpt',
      ),
      NotificationKind.batonAllAnswered => (
        ru ? 'Все ответили' : 'Everyone answered',
        ru
            ? 'Все ответили на ваше «Кто возьмётся?»'
            : "Everyone answered your «Who'll take it?»",
      ),
      NotificationKind.authorInviteReceived => (
        actor,
        excerpt.isNotEmpty
            ? excerpt
            : ru
            ? '$actor зовёт вас помочь'
            : '$actor asks you to help',
      ),
      NotificationKind.authorInviteAccepted => (
        actor,
        ru ? '$actor принял(а) приглашение' : '$actor accepted your invitation',
      ),
      NotificationKind.authorInviteDeclined => (
        actor,
        ru ? '$actor не сможет помочь' : "$actor can't help",
      ),
      NotificationKind.planStepDue => (
        ru ? 'Ваш шаг начался' : 'Your step has started',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planStepTurn => (
        ru ? 'Ваш ход' : 'Your turn',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Предыдущий шаг готов' : 'The previous step is done',
        ),
      ),
      NotificationKind.planChangePending => (
        ru ? 'Ваш шаг изменён' : 'Your step changed',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? '$actor изменил(а) план' : '$actor changed the plan',
        ),
      ),
      NotificationKind.planStepReminder => (
        ru
            ? 'Ваш шаг через ${_minutes(intent.relativeMinutes, ru: true)}'
            : 'Your step starts in ${_minutes(intent.relativeMinutes)}',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planStepOverdue => (
        ru ? 'Ваш шаг просрочен' : 'Your step is overdue',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planStepLate => (
        ru
            ? 'Шаг опаздывает на ${_minutes(intent.relativeMinutes, ru: true)}'
            : 'A step is ${_minutes(intent.relativeMinutes)} late',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planCantMake => (
        ru ? '$actor не успевает' : "$actor can't make it",
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planStepUnassigned => (
        ru ? 'У шага нет исполнителя' : 'A step has no one',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.planEdited => (
        ru ? 'План изменён' : 'Plan updated',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? '$actor изменил(а) план' : '$actor changed the plan',
        ),
      ),
      NotificationKind.planStepDone => (
        ru ? 'Шаг отмечен' : 'A step is done',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru ? 'Шаг плана' : 'Plan step',
        ),
      ),
      NotificationKind.staleRemind => (
        ru ? 'Всё ещё ждёт внимания' : 'Still needs attention',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'В обсуждении запроса что-то ждёт вашего внимания'
              : 'Something in the request thread needs attention',
        ),
      ),
      NotificationKind.inviteAccepted => (
        ru ? 'Приглашение принято' : 'Invitation accepted',
        ru
            ? '$actor принял(а) ваше приглашение'
            : '$actor accepted your invitation',
      ),
      NotificationKind.commitmentAccepted => (
        ru
            ? '$actor принял(а) ${ruItem.yourAcc}'
            : '$actor accepted your $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? '${ruItem.yourNom} принят${ruItem.ending}'
              : 'Your $itemNoun was accepted',
        ),
      ),
      NotificationKind.commitmentResolved => (
        ru ? '$actor закрыл(а) ${ruItem.acc}' : '$actor resolved the $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? '${ruItem.nom} закрыт${ruItem.ending}'
              : 'The $itemNoun was resolved',
        ),
      ),
      NotificationKind.commitmentCancelled => (
        ru
            ? '$actor отменил(а) ${ruItem.acc}'
            : '$actor cancelled the $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? '${ruItem.nom} ${ruItem.cancelled}'
              : 'The $itemNoun was cancelled',
        ),
      ),
      NotificationKind.commitmentRedirected => (
        ru ? '$actor передал(а) это вам' : '$actor reassigned this to you',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: ru
              ? 'Откройте «Общее», чтобы увидеть новое поручение'
              : 'Open General to see your new assignment',
        ),
      ),
    };

    return BeaconNotificationCopy(
      title: title,
      body: body,
      actionUrl: _actionUrl(intent),
      excerpt: excerpt,
    );
  }

  /// Privacy-safe copy for recipients who enabled lock-screen redaction: a
  /// generic, category-level summary with no excerpts, actor names, or beacon
  /// titles. The deep link is preserved (not shown on the lock screen).
  BeaconNotificationCopy lockScreenSafe(BeaconNotificationIntent intent) {
    final (title, body) = switch (categoryOf(intent.kind)) {
      NotificationCategory.asksOfMe => (
        'Tentura',
        'Something needs your response',
      ),
      NotificationCategory.unblocksMe => (
        'Tentura',
        'An update is ready for you',
      ),
      NotificationCategory.coordination => (
        'Tentura',
        'New activity in a request thread',
      ),
      NotificationCategory.connections => (
        'Tentura',
        'New connection activity',
      ),
      NotificationCategory.ambient => ('Tentura', 'New activity'),
    };
    return BeaconNotificationCopy(
      title: title,
      body: body,
      actionUrl: _actionUrl(intent),
    );
  }

  /// A relative duration, never a clock time (plan K16).
  String _minutes(int? minutes, {bool ru = false}) {
    final m = (minutes ?? 0) < 1 ? 1 : minutes!;
    if (m < 60) return ru ? '$m мин' : '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    if (rest == 0) return ru ? '$h ч' : '$h h';
    return ru ? '$h ч $rest мин' : '$h h $rest min';
  }

  String _coordinationItemNoun(int? kind) => switch (kind) {
    coordinationItemKindAsk => 'ask',
    coordinationItemKindPromise => 'promise',
    coordinationItemKindBlocker => 'blocker',
    _ => 'commitment',
  };

  /// Russian forms of the coordination item noun, agreeing in gender (#367).
  ({
    String nom,
    String acc,
    String yourNom,
    String yourAcc,
    String ending,
    String cancelled,
  })
  _ruCoordinationItem(int? kind) => switch (kind) {
    coordinationItemKindAsk => (
      nom: 'Просьба',
      acc: 'просьбу',
      yourNom: 'Ваша просьба',
      yourAcc: 'вашу просьбу',
      ending: 'а',
      cancelled: 'отменена',
    ),
    coordinationItemKindPromise => (
      nom: 'Обещание',
      acc: 'обещание',
      yourNom: 'Ваше обещание',
      yourAcc: 'ваше обещание',
      ending: 'о',
      cancelled: 'отменено',
    ),
    coordinationItemKindBlocker => (
      nom: 'Блокер',
      acc: 'блокер',
      yourNom: 'Ваш блокер',
      yourAcc: 'ваш блокер',
      ending: '',
      cancelled: 'отменён',
    ),
    _ => (
      nom: 'Обязательство',
      acc: 'обязательство',
      yourNom: 'Ваше обязательство',
      yourAcc: 'ваше обязательство',
      ending: 'о',
      cancelled: 'отменено',
    ),
  };

  String _bodyWithRequest({
    required String beaconTitle,
    required String excerpt,
    required String fallback,
  }) {
    final request = beaconTitle.trim();
    if (excerpt.isNotEmpty) {
      if (request.isNotEmpty) return '$request — $excerpt';
      return excerpt;
    }
    if (request.isNotEmpty) return request;
    return fallback;
  }

  String _actionUrl(BeaconNotificationIntent intent) {
    final id = intent.beaconId;
    final item = intent.coordinationItemId;
    final thread = item != null && item.isNotEmpty ? item : 'general';
    final peopleUrl =
        '/#$kPathBeaconView/$id?tab=people&entry=deep_link&is_deep_link=true';
    final roomUrl =
        '/#$kPathBeaconView/$id?tab=threads&thread=$thread'
        '&entry=deep_link&is_deep_link=true';
    final genericUrl = '/#$kPathBeaconView/$id?is_deep_link=true';
    // Step pushes open that step's card (`step=` survives only with
    // `tab=plan`, see the client route normalizer).
    final planStep = item != null && item.isNotEmpty ? '&step=$item' : '';
    final planUrl =
        '/#$kPathBeaconView/$id?tab=plan$planStep&is_deep_link=true';

    return switch (intent.kind) {
      NotificationKind.reviewReady => '/#$kPathReviewContributions/$id',
      NotificationKind.commitmentEvent => peopleUrl,
      NotificationKind.commitmentDeclined ||
      NotificationKind.commitmentRemoved ||
      NotificationKind.commitmentReleased => peopleUrl,
      NotificationKind.newRelay ||
      NotificationKind.authorInviteReceived => genericUrl,
      NotificationKind.authorInviteAccepted ||
      NotificationKind.authorInviteDeclined => peopleUrl,
      NotificationKind.inviteAccepted => '/#/',
      NotificationKind.roomAccess ||
      NotificationKind.needsMe ||
      NotificationKind.staleRemind ||
      NotificationKind.promiseMade ||
      NotificationKind.coordinationChanged ||
      NotificationKind.blockerOpened ||
      NotificationKind.blockerResolved ||
      NotificationKind.roomActivityLowPriority ||
      NotificationKind.roomMention ||
      NotificationKind.postFirstResponse ||
      NotificationKind.commitmentAccepted ||
      NotificationKind.commitmentResolved ||
      NotificationKind.commitmentCancelled ||
      NotificationKind.commitmentRedirected ||
      NotificationKind.batonAsked ||
      NotificationKind.batonTaken ||
      NotificationKind.batonAllAnswered => roomUrl,
      NotificationKind.deadlineChanged ||
      NotificationKind.deadlineReminder => genericUrl,
      NotificationKind.planStepDue ||
      NotificationKind.planStepTurn ||
      NotificationKind.planChangePending ||
      NotificationKind.planStepReminder ||
      NotificationKind.planStepOverdue ||
      NotificationKind.planStepLate ||
      NotificationKind.planCantMake ||
      NotificationKind.planStepUnassigned ||
      NotificationKind.planEdited ||
      NotificationKind.planStepDone => planUrl,
    };
  }
}
