import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/withdraw_reason.dart';
import 'package:tentura_server/domain/entity/forward_helped_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';

import 'invite_accepted_copy.dart';
import 'notification_identity.dart';
import 'notification_text.dart';

/// Localized copy of one notification for one recipient
/// (docs/plans/notification-identity-spec.md §5).
@immutable
class NotificationCopy {
  const NotificationCopy({
    required this.headline,
    required this.sentence,
    this.excerpt,
    this.entityLabel,
  });

  /// The event in a few words, used when there is no readable entity label.
  final String headline;

  /// Who did what, never naming what the recipient may not see.
  final String sentence;

  /// User words the sentence does not already carry; null when none.
  final String? excerpt;

  /// The Request or Post label; null when the recipient cannot read it.
  final String? entityLabel;
}

/// The one RU/EN copy table for every presentation key (spec §5.2). Pure.
class NotificationCopyRenderer {
  const NotificationCopyRenderer();

  static const _postLabelLimit = 40;
  static const _actorLimit = 32;

  static const _withdrawReasons = <String, (String, String)>{
    'cannot_do_it': ('Cannot do it anymore', 'Больше не могу'),
    'timing': ('Timing no longer works', 'Не сходится по времени'),
    'wrong_fit': ('Wrong fit', 'Не мой формат'),
    'someone_else': ('Someone else took over', 'Кто-то другой подхватил'),
    'other': ('Other', 'Другое'),
  };

  static const _hierarchyVerbs = <String, (String, String)>{
    'closed': ('was closed', 'закрыт'),
    'cancelled': ('was cancelled', 'отменён'),
    'reviewOpen': ('entered Final check', 'на подведении итогов'),
    'deleted': ('was deleted', 'удалён'),
  };

  /// Generic copy for recipients who asked for lock-screen redaction: no
  /// label, actor or excerpt.
  ({String title, String body}) lockScreenSafe(
    NotificationCategory category,
    String locale,
  ) {
    final ru = _isRu(locale);
    final (en, ruBody) = switch (category) {
      NotificationCategory.asksOfMe => (
        'Something needs your response',
        'Нужен ваш ответ',
      ),
      NotificationCategory.unblocksMe => (
        'An update is ready for you',
        'Для вас есть обновление',
      ),
      NotificationCategory.coordination => (
        'New activity in a request thread',
        'Новая активность в запросе',
      ),
      NotificationCategory.connections => (
        'New connection activity',
        'Новости о ваших связях',
      ),
      NotificationCategory.ambient => ('New activity', 'Новая активность'),
      NotificationCategory.postsSharedWithMe => (
        'A post was shared with you',
        'С вами поделились постом',
      ),
    };
    return (title: 'Tentura', body: ru ? ruBody : en);
  }

  static const _subjectLimit = 78;
  static const _subjectLabelMin = 16;

  /// Email subject `L — «E»` (Post: `L — E`), at most 78 graphemes: the label
  /// is shortened first (down to 16), then the sentence (spec §4.3). Without
  /// a readable label it is the headline.
  String emailSubject(NotificationCopy copy, {required bool quoteLabel}) {
    final label = copy.entityLabel;
    if (label == null) return copy.headline;
    final (open, close) = quoteLabel ? ('«', '»') : ('', '');
    final overhead = ' — '.length + open.length + close.length;
    final sentenceLength = copy.sentence.characters.length;
    final room = _subjectLimit - overhead - sentenceLength;
    final labelLimit = room < _subjectLabelMin ? _subjectLabelMin : room;
    final shownLabel = NotificationText.truncate(label, labelLimit);
    final sentence = NotificationText.truncate(
      copy.sentence,
      _subjectLimit - overhead - shownLabel.characters.length,
    );
    return '$sentence — $open$shownLabel$close';
  }

  /// Merges co-taker visibility from [coTaker] into [facts] for `baton_taken`.
  static Map<String, Object?> mergeCoTakerFacts(
    Map<String, Object?> facts,
    NotificationIdentity? coTaker,
  ) {
    final withUserId = facts['withUserId'];
    if (withUserId is! String || withUserId.isEmpty) return facts;
    if (coTaker == null || coTaker.actorHidden) {
      return {...facts, 'withUserHidden': true};
    }
    final name = coTaker.actorName;
    if (name == null || NotificationText.normalize(name).isEmpty) {
      return {...facts, 'withUserHidden': true};
    }
    return {...facts, 'withUserName': name};
  }

  /// [presentationKey] is a receipt's `presentation_key`; [facts] its
  /// `presentation_payload`. Throws [ArgumentError] for an unknown key.
  NotificationCopy render({
    required String presentationKey,
    required NotificationKind? kind,
    required Map<String, Object?> facts,
    required NotificationIdentity identity,
    required String locale,
    required int tzOffsetMinutes,
    required DateTime now,
  }) {
    final ru = _isRu(locale);
    String t(String en, String ruText) => ru ? ruText : en;

    final bookmarkOnly = presentationKey == 'closure_opened_bookmark_only';
    final type = bookmarkOnly
        ? AttentionEventType.closureOpened
        : _eventTypeOf(presentationKey);
    final entityScoped = type.isBeaconScoped;
    final readable = identity.readable && !identity.tombstone;

    final actor = _actor(identity, ru);
    final x = readable ? _text(facts['excerpt']) : '';
    String withX(String sentence) => x.isEmpty ? sentence : '$sentence: $x';
    String? date(String key) => switch (DateTime.tryParse(
      _text(facts[key]),
    )) {
      final at? => NotificationText.formatDate(
        at,
        locale,
        tzOffsetMinutes: tzOffsetMinutes,
        now: now,
      ),
      null => null,
    };
    final step = x;
    String withStep(String Function(String s) named, String unnamed) =>
        step.isEmpty ? unnamed : named(NotificationText.quote(step, locale));
    final minutes = NotificationText.minutes(
      _int(facts['relativeMinutes']),
      locale,
    );

    String? excerpt;
    final (String headline, String sentence) = switch (type) {
      AttentionEventType.relayReceived =>
        identity.entityKind == NotificationEntityKind.post
            ? (
                t('Post shared', 'Поделились постом'),
                t(
                  '$actor shared a post with you',
                  '$actor делится с вами постом',
                ),
              )
            : (
                t('Request forwarded', 'Запрос переслан'),
                t(
                  '$actor forwarded you a request',
                  '$actor пересылает вам запрос',
                ),
              ),
      AttentionEventType.helpOfferSubmitted => (
        t('Help offered', 'Предложена помощь'),
        facts['isBackupOffer'] == true
            ? t(
                '$actor offered to help as backup',
                '$actor предлагает помощь как запасной вариант',
              )
            : t('$actor offered help', '$actor предлагает помощь'),
      ),
      AttentionEventType.helpWithdrawn => (
        t('Help offer withdrawn', 'Предложение помощи отозвано'),
        t(
              '$actor withdrew their help offer',
              '$actor отозвал(а) предложение помощи',
            ) +
            switch (_withdrawReason(facts)) {
              final reason? => ' (${ru ? reason.$2 : reason.$1})',
              null => '',
            },
      ),
      AttentionEventType.forwardDeclined => (
        t("Can't help", 'Не может помочь'),
        t("$actor can't help", '$actor не может помочь'),
      ),
      AttentionEventType.offerAccepted => (
        t('Offer accepted', 'Предложение принято'),
        t('$actor accepted your offer', '$actor принял(а) ваше предложение'),
      ),
      AttentionEventType.offerDeclined => (
        t('Offer declined', 'Предложение отклонено'),
        t('$actor declined your offer', '$actor отклонил(а) ваше предложение'),
      ),
      AttentionEventType.offerRemoved => (
        t('Removed from the discussion', 'Вас убрали из обсуждения'),
        t(
          '$actor removed you from the discussion',
          '$actor убрал(а) вас из обсуждения',
        ),
      ),
      AttentionEventType.commitmentReleased => (
        t('Participation ended', 'Участие завершено'),
        t(
          '$actor ended your participation',
          '$actor завершил(а) ваше участие',
        ),
      ),
      // Questions text never leaves the room, so it is checked first.
      AttentionEventType.roomMessagePosted
          when _text(facts['coordinationItemId']).isNotEmpty =>
        (
          t('New message in Questions', 'Новое сообщение в вопросах'),
          t('$actor wrote in Questions', '$actor пишет в вопросах'),
        ),
      AttentionEventType.roomMessagePosted
          when kind == NotificationKind.roomMention =>
        (
          t('You were mentioned', 'Вас упомянули'),
          withX(t('$actor mentioned you', '$actor упоминает вас')),
        ),
      AttentionEventType.roomMessagePosted => (
        t('New message', 'Новое сообщение'),
        x.isNotEmpty
            ? '$actor: $x'
            : t('$actor sent a message', '$actor: новое сообщение'),
      ),
      AttentionEventType.postFirstResponse => (
        t('Reply to your post', 'Ответ на ваш пост'),
        withX(t('$actor replied to your post', '$actor отвечает на ваш пост')),
      ),
      AttentionEventType.postExpiringSoon => (
        t('Your post expires soon', 'Ваш пост скоро исчезнет'),
        switch (_hoursLeft(facts['expiresAt'], now)) {
              final h? => t('Expires in $h h. ', 'Исчезнет через $h ч. '),
              null => t('Expires soon. ', 'Скоро исчезнет. '),
            } +
            t(
              'Turn it into a request to keep it going',
              'Оформите запрос, чтобы продолжить',
            ),
      ),
      AttentionEventType.postRequestCreated => (
        t('Request created', 'Запрос создан'),
        t('You created a request from a post', 'Вы создали запрос из поста'),
      ),
      AttentionEventType.requestStatusChanged => (
        t('Status changed', 'Статус изменён'),
        switch (_text(facts['toStatus'])) {
          '' => t('$actor changed the status', '$actor: статус изменён'),
          final status => () {
            final label = NotificationText.quote(
              NotificationText.statusLabel(status, locale),
              locale,
            );
            return t(
              '$actor changed the status to $label',
              '$actor: статус $label',
            );
          }(),
        },
      ),
      AttentionEventType.beaconHierarchyStatusChanged => () {
        final (en, ruVerb) =
            _hierarchyVerbs[_text(facts['toStatus'])] ??
            ('was updated', 'изменён');
        final related = _text(identity.relatedLabel);
        final named = related.isEmpty
            ? ''
            : ' ${NotificationText.quote(related, locale)}';
        return (
          t('Linked request updated', 'Связанный запрос изменён'),
          related.isEmpty
              ? t('A linked request $en', 'Связанный запрос $ruVerb')
              : t('Linked request$named $en', 'Связанный запрос$named $ruVerb'),
        );
      }(),
      AttentionEventType.deadlineChanged => (
        t('Deadline changed', 'Срок изменён'),
        switch (date('newEndAt')) {
          final d? => t(
            '$actor moved the deadline to $d',
            '$actor: новый срок — $d',
          ),
          null => t('$actor removed the deadline', '$actor убрал(а) срок'),
        },
      ),
      AttentionEventType.deadlineReminder => (
        t('Deadline tomorrow', 'Срок завтра'),
        switch (date('newEndAt')) {
          final d? => t('Deadline: $d', 'Срок: $d'),
          null => t('The deadline is tomorrow', 'Срок — завтра'),
        },
      ),
      AttentionEventType.coordinationChanged => (
        t('Coordination changed', 'Договорённости изменились'),
        x.isEmpty
            ? t(
                '$actor updated the coordination',
                '$actor: договорённости изменились',
              )
            : t(
                '$actor updated the coordination: $x',
                '$actor: договорённости изменились — $x',
              ),
      ),
      AttentionEventType.batonAsked => (
        t("Who'll take it?", 'Кто возьмётся?'),
        withX(
          t(
            '$actor asks if you can help',
            '$actor спрашивает, сможете ли вы помочь',
          ),
        ),
      ),
      AttentionEventType.batonPartnerAsked => (
        t('Take it on together?', 'Взяться вместе?'),
        withX(
          t(
            '$actor wants to take it on together with you',
            '$actor предлагает взяться вместе',
          ),
        ),
      ),
      AttentionEventType.batonPartnerAnswered =>
        facts['accepted'] == true
            ? (
                t('Together', 'Вместе'),
                withX(
                  t(
                    '$actor will take it on with you',
                    '$actor возьмётся вместе с вами',
                  ),
                ),
              )
            : (
                t("Can't join", 'Не сможет присоединиться'),
                withX(
                  t(
                    "$actor can't join you. Answer again",
                    '$actor не сможет присоединиться. Ответьте ещё раз',
                  ),
                ),
              ),
      AttentionEventType.batonTaken => () {
        final partner = _visibleCoTakerName(facts);
        if (partner != null) {
          return (
            t('You took it', 'Вы взялись'),
            withX(t('You and $partner took it', 'Вы и $partner взялись')),
          );
        }
        return (
          t('You took it', 'Вы взялись'),
          withX(t('You took it', 'Вы взялись')),
        );
      }(),
      AttentionEventType.batonAllAnswered => (
        t('Everyone answered', 'Все ответили'),
        t(
          "Everyone answered your «Who'll take it?»",
          'Все ответили на ваше «Кто возьмётся?»',
        ),
      ),
      AttentionEventType.authorInviteReceived => (
        t('Invitation to help', 'Приглашение помочь'),
        withX(t('$actor asks you to help', '$actor зовёт вас помочь')),
      ),
      AttentionEventType.authorInviteAccepted => (
        t('Invitation accepted', 'Приглашение принято'),
        t(
          '$actor accepted your invitation',
          '$actor принял(а) ваше приглашение',
        ),
      ),
      AttentionEventType.authorInviteDeclined => (
        t("Can't make it", 'Не сможет'),
        t("$actor can't make it", '$actor не сможет помочь'),
      ),
      AttentionEventType.planStepDue => (
        t('Your step has started', 'Ваш шаг начался'),
        withStep(
          (s) => t('Your step $s has started', 'Ваш шаг $s начался'),
          t('Your step has started', 'Ваш шаг начался'),
        ),
      ),
      AttentionEventType.planStepTurn => (
        t('Your turn', 'Ваш ход'),
        withStep(
          (s) => t('Your turn: $s', 'Ваш ход: $s'),
          t('Your turn', 'Ваш ход'),
        ),
      ),
      AttentionEventType.planChangePending => (
        t('Your step changed', 'Ваш шаг изменён'),
        withStep(
          (s) =>
              t('$actor changed your step $s', '$actor изменил(а) ваш шаг $s'),
          t('$actor changed your step', '$actor изменил(а) ваш шаг'),
        ),
      ),
      AttentionEventType.planStepReminder => (
        t('Step soon', 'Скоро ваш шаг'),
        withStep(
          (s) => t(
            'Your step $s starts in $minutes',
            'Ваш шаг $s через $minutes',
          ),
          t('Your step starts in $minutes', 'Ваш шаг через $minutes'),
        ),
      ),
      AttentionEventType.planStepOverdue => (
        t('Step overdue', 'Шаг просрочен'),
        withStep(
          (s) => t('Your step $s is overdue', 'Ваш шаг $s просрочен'),
          t('Your step is overdue', 'Ваш шаг просрочен'),
        ),
      ),
      AttentionEventType.planStepLate => (
        t('Step running late', 'Шаг опаздывает'),
        withStep(
          (s) => t('$s is $minutes late', '$s опаздывает на $minutes'),
          t('A step is $minutes late', 'Шаг опаздывает на $minutes'),
        ),
      ),
      AttentionEventType.planCantMake => (
        t("Can't make it", 'Не успевает'),
        withStep(
          (s) => t("$actor can't make $s", '$actor не успевает к шагу $s'),
          t("$actor can't make their step", '$actor не успевает к шагу'),
        ),
      ),
      AttentionEventType.planStepUnassigned => (
        t('Step has no one', 'Шаг без исполнителя'),
        withStep(
          (s) => t('$s has no one', 'У шага $s нет исполнителя'),
          t('A step has no one', 'У шага нет исполнителя'),
        ),
      ),
      AttentionEventType.planEdited => (
        t('Plan updated', 'План изменён'),
        t('$actor edited the plan', '$actor изменил(а) план'),
      ),
      AttentionEventType.planStepDone => (
        t('Step done', 'Шаг выполнен'),
        withStep(
          (s) => t('$actor finished $s', '$actor: шаг $s выполнен'),
          t('$actor finished a step', '$actor: шаг выполнен'),
        ),
      ),
      AttentionEventType.forwardHelped => (
        t('Your forward helped', 'Ваша пересылка помогла'),
        forwardHelpedSentence(
          ForwardHelpedContent.fromPayload({
            ...facts,
            'eventType': 'forwardHelped',
            'beaconTitle': '',
          }),
          label: readable ? _text(identity.label) : '',
          locale: locale,
        ),
      ),
      AttentionEventType.closureOpened => (
        t('Time to sum up', 'Пора подвести итоги'),
        bookmarkOnly
            ? t('Closing is open', 'Подведение итогов открыто')
            : t(
                'Closing is open: mark who helped',
                'Подведение итогов открыто: отметьте, кто помог',
              ),
      ),
      AttentionEventType.closureDraftReminder => (
        t('Finish your review', 'Завершите свою оценку'),
        t(
          "Your review isn't sent yet; closing ends within a day",
          'Ваша оценка ещё не отправлена; итоги закроются в течение суток',
        ),
      ),
      AttentionEventType.closureFinalized => (
        t('Request closed', 'Запрос закрыт'),
        t('The results are in', 'Итоги подведены'),
      ),
      AttentionEventType.closureCancelled => (
        t('Closing cancelled', 'Подведение итогов отменено'),
        _text(facts['actorUserId']).isEmpty
            ? t('Closing was cancelled', 'Подведение итогов отменено')
            : t(
                '$actor cancelled the closing',
                '$actor отменил(а) подведение итогов',
              ),
      ),
      AttentionEventType.requestStale => (
        t('Your request has gone quiet', 'В вашем запросе стало тихо'),
        _staleSentence(facts, locale, date('endAt')),
      ),
      AttentionEventType.mutualConnectionFormed => (
        t('New connection', 'Новая связь'),
        t('You and $actor are now connected', 'Вы и $actor теперь на связи'),
      ),
      AttentionEventType.inviteAccepted => () {
        final origin = switch (_text(facts['inviteOrigin'])) {
          'new_account' => InviteAcceptedCopy.newAccount,
          'existing_account' => InviteAcceptedCopy.existingAccount,
          _ => InviteAcceptedCopy.connected,
        };
        return (
          t('Invitation accepted', 'Приглашение принято'),
          t(
            '$actor accepted your invitation. ${origin.en}',
            '$actor принял(а) ваше приглашение. ${origin.ru}',
          ),
        );
      }(),
      // Declared but never written (§5.2): `{A} · H`.
      AttentionEventType.needsMe => _dotted(
        actor,
        t('Asked of you', 'Вас просят'),
      ),
      AttentionEventType.blockerOpened => _dotted(
        actor,
        t('Blocker opened', 'Появился блокер'),
      ),
      AttentionEventType.blockerResolved => _dotted(
        actor,
        t('Blocker resolved', 'Блокер снят'),
      ),
      AttentionEventType.promiseMade => _dotted(
        actor,
        t('New promise', 'Новое обещание'),
      ),
      AttentionEventType.promiseWithdrawn => _dotted(
        actor,
        t('Promise withdrawn', 'Обещание отозвано'),
      ),
      AttentionEventType.staleReminder => _dotted(
        actor,
        t('Still needs attention', 'Всё ещё ждёт внимания'),
      ),
      AttentionEventType.obligationEnded => _dotted(
        actor,
        t('Obligation ended', 'Обязательство завершено'),
      ),
      AttentionEventType.commitmentAccepted => _dotted(
        actor,
        t('Commitment accepted', 'Обязательство принято'),
      ),
      AttentionEventType.commitmentResolved => _dotted(
        actor,
        t('Commitment resolved', 'Обязательство выполнено'),
      ),
      AttentionEventType.commitmentCancelled => _dotted(
        actor,
        t('Commitment cancelled', 'Обязательство отменено'),
      ),
      AttentionEventType.commitmentRedirected => _dotted(
        actor,
        t('Reassigned to you', 'Передано вам'),
      ),
    };
    // User words the sentence does not quote itself.
    if (type
        case AttentionEventType.relayReceived ||
            AttentionEventType.helpOfferSubmitted ||
            AttentionEventType.helpWithdrawn ||
            AttentionEventType.forwardDeclined when x.isNotEmpty) {
      excerpt = x;
    }
    return NotificationCopy(
      headline: headline,
      sentence: sentence,
      excerpt: excerpt,
      entityLabel: entityScoped ? _entityLabel(identity, ru) : null,
    );
  }

  /// Today's forward-helped sentences (path → helper), naming the Request
  /// only when [label] is non-empty.
  static String forwardHelpedSentence(
    ForwardHelpedContent? content, {
    required String label,
    required String locale,
  }) {
    final ru = _isRu(locale);
    final nodes = content?.path ?? const [];
    final path = nodes
        .map(
          (node) =>
              node.displayName ??
              (ru
                  ? '${node.anonymousCount} чел.'
                  : '${node.anonymousCount} people'),
        )
        .join(' → ');
    var helper = ru ? 'участника' : 'a helper';
    for (final node in nodes) {
      if (node.displayName case final name?
          when node.userId == content?.helperId) {
        helper = name;
      }
    }
    final who = path.isEmpty ? (ru ? 'Кто-то' : 'Someone') : path;
    if (label.isEmpty) {
      return content?.done ?? false
          ? (ru
                ? 'Завершён с помощью $helper'
                : "Completed with $helper's help")
          : (ru ? '$who предложил(а) помощь' : '$who offered help');
    }
    return content?.done ?? false
        ? (ru
              ? '«$label» завершён с помощью $helper'
              : "«$label» was completed with $helper's help")
        : (ru
              ? '$who предложил(а) помощь с «$label»'
              : '$who offered help with «$label»');
  }

  static (String, String) _dotted(String actor, String headline) =>
      (headline, '$actor · $headline');

  static String _staleSentence(
    Map<String, Object?> facts,
    String locale,
    String? endAt,
  ) {
    final ru = _isRu(locale);
    if (facts['staleReason'] == 'deadlinePassed' && endAt != null) {
      return ru
          ? 'Срок прошёл $endAt. Закройте или продлите запрос'
          : 'The deadline passed on $endAt. Close it or extend it';
    }
    final days = _int(facts['quietDays']);
    final quiet = days == null
        ? (ru ? 'Давно без движения' : 'No activity for a while')
        : ru
        ? '$days ${NotificationText.plural(days, locale, one: 'день', few: 'дня', many: 'дней')} без движения'
        : 'No activity for $days ${NotificationText.plural(days, locale, one: 'day', few: 'days', many: 'days')}';
    return ru
        ? '$quiet. Закройте, продлите или напишите новости'
        : '$quiet. Close it, extend it or post an update';
  }

  static String? _entityLabel(NotificationIdentity identity, bool ru) {
    final isPost = identity.entityKind == NotificationEntityKind.post;
    if (identity.tombstone) {
      return isPost
          ? (ru ? 'Удалённый пост' : 'Deleted post')
          : (ru ? 'Удалённый запрос' : 'Deleted request');
    }
    if (!identity.readable) return null;
    final label = _text(identity.label);
    if (!isPost) return label.isEmpty ? null : label;
    if (label.isNotEmpty) {
      final text = NotificationText.truncate(label, _postLabelLimit);
      return ru ? 'Пост: $text' : 'Post: $text';
    }
    if (identity.hasImage) return ru ? 'Пост с фото' : 'Post with a photo';
    final author = _text(identity.authorName);
    if (author.isEmpty) return ru ? 'Пост' : 'Post';
    return ru ? 'Пост · $author' : 'Post · $author';
  }

  static String _actor(NotificationIdentity identity, bool ru) {
    final name = identity.actorHidden ? '' : _text(identity.actorName);
    if (name.isEmpty) return ru ? 'Кто-то' : 'Someone';
    return NotificationText.truncate(name, _actorLimit);
  }

  static (String, String)? _withdrawReason(Map<String, Object?> facts) {
    final key = _text(facts['withdrawReason']);
    return isAllowedWithdrawReason(key) ? _withdrawReasons[key] : null;
  }

  static int? _hoursLeft(Object? expiresAt, DateTime now) {
    final at = DateTime.tryParse(_text(expiresAt));
    if (at == null) return null;
    final minutes = at.difference(now).inMinutes;
    final hours = (minutes / 60).ceil();
    return hours < 1 ? 1 : hours;
  }

  /// Whether [render] can render [key]; rows with any other (legacy) key never
  /// can.
  static bool isRenderableKey(String key) =>
      key == 'closure_opened_bookmark_only' ||
      AttentionEventType.values.any((type) => _snake(type.name) == key);

  static AttentionEventType _eventTypeOf(String key) {
    for (final type in AttentionEventType.values) {
      if (_snake(type.name) == key) return type;
    }
    throw ArgumentError.value(key, 'presentationKey', 'Unknown key');
  }

  static String? _visibleCoTakerName(Map<String, Object?> facts) {
    if (facts['withUserHidden'] == true) return null;
    final name = _text(facts['withUserName']);
    if (name.isEmpty) return null;
    return NotificationText.truncate(name, _actorLimit);
  }

  static String _snake(String camel) => camel.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );

  static String _text(Object? value) =>
      value is String ? NotificationText.normalize(value) : '';

  static int? _int(Object? value) => value is int ? value : null;

  static bool _isRu(String locale) => locale.toLowerCase().startsWith('ru');
}
