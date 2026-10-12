import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_revision.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_room_line.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_history_screen.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// How many changes a revision line lists before «ещё N» (mockup §11).
const kPlanRoomLineMaxChanges = 3;

/// A plan system line in the discussion (`system_message_kind = 5`, markers
/// 13..16, plan §5.10): revisions, coalesced ticks, «Не успеваю» and copies.
/// Thin centered lines like the fact lines; a broken payload falls back to
/// «Изменение плана».
class RoomPlanLine extends StatelessWidget {
  const RoomPlanLine({
    required this.message,
    required this.actorName,
    required this.nameOf,
    this.people = const [],
    this.onOpenHistory,
    super.key,
  });

  final RoomMessage message;

  /// Display name of the message author (the actor).
  final String actorName;

  /// Display name of anyone the payload mentions.
  final String Function(String? userId) nameOf;

  /// Admitted people, for the history screen.
  final List<Profile> people;

  /// Opens the plan history at a revision; defaults to [openPlanHistory].
  final void Function(BuildContext context, int revisionSeq)? onOpenHistory;

  static const fallbackKey = Key('room-plan-line-fallback');
  static const historyKey = Key('room-plan-line-history');

  void _openHistory(BuildContext context, int seq) {
    final open = onOpenHistory;
    if (open != null) {
      open(context, seq);
      return;
    }
    unawaited(
      openPlanHistory(
        context,
        beaconId: message.beaconId,
        people: PlanPeople(admitted: people),
        focusSeq: seq,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final line = PlanRoomLine.tryParse(
      marker: message.semanticMarker,
      payloadJson: message.systemPayloadJson,
    );
    return switch (line) {
      final PlanRevisedLine revised => _RevisedLine(
        line: revised,
        actorName: actorName,
        nameOf: nameOf,
        onHistory: (ctx) => _openHistory(ctx, revised.revisionSeq),
      ),
      final PlanStepsDoneLine done => _TicksLine(line: done, nameOf: nameOf),
      final PlanCantMakeLine cantMake => _CantMakeLine(
        line: cantMake,
        actorName: actorName,
        nameOf: nameOf,
        onHistory: cantMake.revisionSeq == null
            ? null
            : (ctx) => _openHistory(ctx, cantMake.revisionSeq!),
      ),
      final PlanCopiedLine copied => _CopiedLine(line: copied),
      null => _PlanLineFrame(
        key: fallbackKey,
        icon: Icons.checklist_outlined,
        headline: l10n.planLineFallback,
      ),
    };
  }
}

class _RevisedLine extends StatelessWidget {
  const _RevisedLine({
    required this.line,
    required this.actorName,
    required this.nameOf,
    required this.onHistory,
  });

  final PlanRevisedLine line;
  final String actorName;
  final String Function(String? userId) nameOf;
  final void Function(BuildContext context) onHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final headline = switch (line.kind) {
      PlanRevisionKind.created => l10n.planLineCreated(actorName),
      PlanRevisionKind.restored => l10n.planLineRestored(
        actorName,
        line.restoredFromSeq ?? 0,
      ),
      PlanRevisionKind.unassignedOnLeave => l10n.planLineUnassigned(
        nameOf(line.subjectUserId ?? line.actorId),
        line.changeCount,
      ),
      _ => l10n.planLineRevised(actorName),
    };
    final shown = line.changes.take(kPlanRoomLineMaxChanges).toList();
    final more = line.changeCount - shown.length;
    return _PlanLineFrame(
      icon: Icons.checklist_outlined,
      headline: headline,
      details: [
        for (final text in planChangeLines(
          changes: shown,
          nameOf: nameOf,
          l10n: l10n,
        ))
          _PlanLineDetail(text: text),
        if (more > 0) _PlanLineDetail(text: l10n.planLineMore(more)),
        if (line.comment.isNotEmpty)
          _PlanLineDetail(text: '«${line.comment}»', italic: true),
      ],
      action: TenturaTextAction(
        key: RoomPlanLine.historyKey,
        label: l10n.planLineHistory,
        onPressed: () => onHistory(context),
      ),
    );
  }
}

class _TicksLine extends StatelessWidget {
  const _TicksLine({required this.line, required this.nameOf});

  final PlanStepsDoneLine line;
  final String Function(String? userId) nameOf;

  String _tickText(L10n l10n, PlanTickEntry t) => t.tickedForOther
      ? l10n.planLineDoneFor(nameOf(t.actorId), nameOf(t.assigneeId), t.title)
      : l10n.planLineDoneOwn(nameOf(t.actorId ?? t.assigneeId), t.title);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final ticks = line.ticks;
    if (ticks.length == 1) {
      final t = ticks.single;
      return _PlanLineFrame(
        icon: Icons.check_circle_outline,
        headline: _tickText(l10n, t),
        struck: t.isUndone,
        trailingNote: t.isUndone ? l10n.planLineTickUndone : null,
      );
    }
    return _PlanLineFrame(
      icon: Icons.check_circle_outline,
      headline: l10n.planLineDoneMany(ticks.length),
      details: [
        for (final t in ticks)
          _PlanLineDetail(
            text: _tickText(l10n, t),
            struck: t.isUndone,
            note: t.isUndone ? l10n.planLineTickUndone : null,
          ),
      ],
    );
  }
}

class _CantMakeLine extends StatelessWidget {
  const _CantMakeLine({
    required this.line,
    required this.actorName,
    required this.nameOf,
    this.onHistory,
  });

  final PlanCantMakeLine line;
  final String actorName;
  final String Function(String? userId) nameOf;
  final void Function(BuildContext context)? onHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final name = line.actorId == null ? actorName : nameOf(line.actorId);
    final shift = line.shift;
    final movedTo = line.movedTo;
    final headline = switch (line.option) {
      PlanCantMakeLineOption.handover => l10n.planLineCantMakeHanded(
        name,
        line.title,
        nameOf(line.toUserId),
      ),
      PlanCantMakeLineOption.reschedule when shift != null =>
        l10n.planLineCantMakeMoved(
          name,
          line.title,
          planSignedDuration(shift, l10n),
        ),
      PlanCantMakeLineOption.reschedule when movedTo != null =>
        l10n.planLineCantMakeMovedTo(
          name,
          line.title,
          planDayTime(movedTo, l10n.localeName),
        ),
      _ => l10n.planLineFallback,
    };
    return _PlanLineFrame(
      icon: Icons.schedule,
      headline: headline,
      onTap: onHistory == null ? null : () => onHistory!(context),
    );
  }
}

class _CopiedLine extends StatelessWidget {
  const _CopiedLine({required this.line});

  final PlanCopiedLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<PlanCubit?>();
    String text(String? title) => title == null || title.trim().isEmpty
        ? l10n.planLineCopiedUnknown
        : l10n.planLineCopied(title.trim());
    if (cubit == null) {
      return _PlanLineFrame(
        icon: Icons.content_copy_outlined,
        headline: text(null),
      );
    }
    // The server names the source only when the viewer can read it.
    return BlocBuilder<PlanCubit, PlanState>(
      bloc: cubit,
      buildWhen: (p, c) =>
          p.plan?.copiedFromTitle != c.plan?.copiedFromTitle ||
          p.plan?.copiedFromBeaconId != c.plan?.copiedFromBeaconId,
      builder: (context, state) {
        final plan = state.plan;
        final title =
            plan != null && plan.copiedFromBeaconId == line.sourceBeaconId
            ? plan.copiedFromTitle
            : null;
        return _PlanLineFrame(
          icon: Icons.content_copy_outlined,
          headline: text(title),
        );
      },
    );
  }
}

/// `+1 h` / `−30 min`: a signed compact duration.
String planSignedDuration(Duration d, L10n l10n) {
  final sign = d.isNegative ? '−' : '+';
  return '$sign${planDuration(d.abs(), l10n)}';
}

/// Centered thin system line: icon + headline, optional detail lines and a
/// trailing text action.
class _PlanLineFrame extends StatelessWidget {
  const _PlanLineFrame({
    required this.icon,
    required this.headline,
    this.details = const [],
    this.action,
    this.struck = false,
    this.trailingNote,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String headline;
  final List<Widget> details;
  final Widget? action;
  final bool struck;
  final String? trailingNote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final muted = tt.textMuted;
    final headlineStyle = TenturaText.bodySmall(muted).copyWith(
      decoration: struck ? TextDecoration.lineThrough : null,
    );
    Widget headlineRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: tt.iconSize * 0.75, color: muted),
        SizedBox(width: tt.tightGap),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: headline, style: headlineStyle),
                if (trailingNote != null)
                  TextSpan(
                    text: ' · $trailingNote',
                    style: TenturaText.bodySmall(muted),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (onTap != null) {
      headlineRow = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tt.tightGap),
          child: headlineRow,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.tightGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          headlineRow,
          ...details,
          ?action,
        ],
      ),
    );
  }
}

class _PlanLineDetail extends StatelessWidget {
  const _PlanLineDetail({
    required this.text,
    this.italic = false,
    this.struck = false,
    this.note,
  });

  final String text;
  final bool italic;
  final bool struck;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final style = TenturaText.bodySmall(tt.textMuted).copyWith(
      fontStyle: italic ? FontStyle.italic : null,
      decoration: struck ? TextDecoration.lineThrough : null,
    );
    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text, style: style),
            if (note != null)
              TextSpan(
                text: ' · $note',
                style: TenturaText.bodySmall(tt.textMuted),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
