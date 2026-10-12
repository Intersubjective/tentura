import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_plan.dart';
import '../util/plan_presenter.dart';

/// Panel width from which the Plan tab offers «По людям» (plan §5.4, D6).
const kPlanMatrixMinWidth = 600.0;

/// Width of the trailing «Без времени» column on wide panels.
const kPlanMatrixAsideMinWidth = 840.0;

/// How long a step with only a start (or only an end) is drawn (P18).
const kPlanMatrixOpenBlock = Duration(minutes: 30);

const double _hourWidth = 72;
const double _rowHeight = 52;
const double _nameColumnWidth = 128;
const double _asideWidth = 240;
const double _nowLineWidth = 2;

/// One timed step placed on the time axis.
@immutable
final class PlanMatrixBlock {
  const PlanMatrixBlock({
    required this.step,
    required this.start,
    required this.end,
    this.openStart = false,
    this.openEnd = false,
  });

  final PlanStep step;
  final DateTime start;
  final DateTime end;

  /// Only an end is known: a 30-min block ending at it.
  final bool openStart;

  /// Only a start is known: a 30-min block starting at it.
  final bool openEnd;

  /// The local day the block belongs to (start, else end — P18).
  DateTime get day {
    final anchor = (step.startAt ?? step.endAt ?? start).toLocal();
    return DateTime(anchor.year, anchor.month, anchor.day);
  }
}

/// Places the timed steps of a plan; untimed steps are not blocks.
List<PlanMatrixBlock> planMatrixBlocks(List<PlanStep> steps) => [
  for (final s in steps)
    if (s.startAt != null && s.endAt != null && s.endAt!.isAfter(s.startAt!))
      PlanMatrixBlock(step: s, start: s.startAt!, end: s.endAt!)
    else if (s.startAt != null)
      PlanMatrixBlock(
        step: s,
        start: s.startAt!,
        end: s.startAt!.add(kPlanMatrixOpenBlock),
        openEnd: s.endAt == null,
      )
    else if (s.endAt != null)
      PlanMatrixBlock(
        step: s,
        start: s.endAt!.subtract(kPlanMatrixOpenBlock),
        end: s.endAt!,
        openStart: true,
      ),
];

/// Local days that carry blocks, in order.
List<DateTime> planMatrixDays(List<PlanMatrixBlock> blocks) {
  final days = {for (final b in blocks) b.day}.toList()..sort();
  return days;
}

/// The day to open on: today when it has blocks, else the first later day,
/// else the last one.
int planMatrixInitialDay(List<DateTime> days, DateTime now) {
  if (days.isEmpty) return 0;
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  for (var i = 0; i < days.length; i++) {
    if (!days[i].isBefore(today)) return i;
  }
  return days.length - 1;
}

/// Row keys of the matrix: assignees in plan order, then «Нет исполнителя»
/// (null) when a step has none.
List<String?> planMatrixRows(List<PlanStep> steps) {
  final ids = <String>[];
  var unassigned = false;
  for (final s in steps) {
    final id = s.assigneeId;
    if (id == null) {
      unassigned = true;
    } else if (!ids.contains(id)) {
      ids.add(id);
    }
  }
  return [...ids, if (unassigned) null];
}

/// «Люди × время» (plan §5.4): rows are people, columns the hours of the
/// chosen day; untimed steps are listed aside. Tap a block for the step card.
class PlanPeopleMatrix extends StatefulWidget {
  const PlanPeopleMatrix({
    required this.plan,
    required this.people,
    required this.now,
    this.onOpenStep,
    super.key,
  });

  final BeaconPlan plan;
  final PlanPeople people;
  final DateTime now;
  final ValueChanged<String>? onOpenStep;

  static const matrixKey = Key('plan-matrix');
  static const prevDayKey = Key('plan-matrix-prev-day');
  static const nextDayKey = Key('plan-matrix-next-day');
  static const nowLineKey = Key('plan-matrix-now');
  static const untimedKey = Key('plan-matrix-untimed');
  static Key blockKey(String stepId) => Key('plan-matrix-block-$stepId');
  static Key rowKey(String? userId) => Key('plan-matrix-row-${userId ?? '-'}');

  @override
  State<PlanPeopleMatrix> createState() => _PlanPeopleMatrixState();
}

class _PlanPeopleMatrixState extends State<PlanPeopleMatrix> {
  int? _dayIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final steps = widget.plan.steps;
    final blocks = planMatrixBlocks(steps);
    final days = planMatrixDays(blocks);
    final dayIndex = math.min(
      _dayIndex ?? planMatrixInitialDay(days, widget.now),
      math.max(0, days.length - 1),
    );
    final day = days.isEmpty ? null : days[dayIndex];
    final dayBlocks = [
      for (final b in blocks)
        if (b.day == day) b,
    ];
    final untimed = [
      for (final s in steps)
        if (s.isUntimed) s,
    ];
    final rows = planMatrixRows(steps);

    final grid = day == null || dayBlocks.isEmpty
        ? Padding(
            padding: tt.cardPadding,
            child: Text(
              l10n.planMatrixNoTimedSteps,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          )
        : _Grid(
            day: day,
            blocks: dayBlocks,
            rows: rows,
            people: widget.people,
            now: widget.now,
            onOpenStep: widget.onOpenStep,
          );

    final dayBar = Row(
      children: [
        IconButton(
          key: PlanPeopleMatrix.prevDayKey,
          tooltip: l10n.planMatrixPrevDay,
          icon: const Icon(Icons.chevron_left),
          onPressed: dayIndex > 0
              ? () => setState(() => _dayIndex = dayIndex - 1)
              : null,
        ),
        Expanded(
          child: Text(
            day == null ? '' : planDayLabel(day, l10n.localeName),
            textAlign: TextAlign.center,
            style: TenturaText.typeLabel(tt.text),
          ),
        ),
        IconButton(
          key: PlanPeopleMatrix.nextDayKey,
          tooltip: l10n.planMatrixNextDay,
          icon: const Icon(Icons.chevron_right),
          onPressed: dayIndex < days.length - 1
              ? () => setState(() => _dayIndex = dayIndex + 1)
              : null,
        ),
      ],
    );

    final aside = untimed.isEmpty
        ? null
        : _UntimedList(
            steps: untimed,
            people: widget.people,
            onOpenStep: widget.onOpenStep,
          );

    return LayoutBuilder(
      key: PlanPeopleMatrix.matrixKey,
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kPlanMatrixAsideMinWidth;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [if (days.isNotEmpty) dayBar, grid],
        );
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: wide && aside != null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    SizedBox(width: tt.sectionGap),
                    SizedBox(width: _asideWidth, child: aside),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    main,
                    if (aside != null) ...[
                      SizedBox(height: tt.sectionGap),
                      aside,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.day,
    required this.blocks,
    required this.rows,
    required this.people,
    required this.now,
    this.onOpenStep,
  });

  final DateTime day;
  final List<PlanMatrixBlock> blocks;
  final List<String?> rows;
  final PlanPeople people;
  final DateTime now;
  final ValueChanged<String>? onOpenStep;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    // Hours of the day the blocks cover, at least four.
    var firstHour = 24;
    var lastHour = 0;
    for (final b in blocks) {
      final s = b.start.toLocal();
      final e = b.end.toLocal();
      final startHour = s.isBefore(day) ? 0 : s.hour;
      final endOfDay = day.add(const Duration(days: 1));
      final endHour = !e.isBefore(endOfDay)
          ? 24
          : e.hour + (e.minute > 0 || e.second > 0 ? 1 : 0);
      firstHour = math.min(firstHour, startHour);
      lastHour = math.max(lastHour, endHour);
    }
    if (lastHour - firstHour < 4) {
      lastHour = math.min(24, firstHour + 4);
      firstHour = math.max(0, lastHour - 4);
    }
    final origin = day.add(Duration(hours: firstHour));
    final hours = lastHour - firstHour;
    final width = hours * _hourWidth;
    double x(DateTime t) {
      final minutes = t.toLocal().difference(origin).inSeconds / 60;
      return (minutes / 60 * _hourWidth).clamp(0, width).toDouble();
    }

    final localNow = now.toLocal();
    final showNow =
        !localNow.isBefore(origin) &&
        localNow.isBefore(origin.add(Duration(hours: hours)));

    final rowWidgets = <Widget>[
      for (final userId in rows)
        SizedBox(
          key: PlanPeopleMatrix.rowKey(userId),
          height: _rowHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: tt.borderSubtle)),
                  ),
                ),
              ),
              for (final b in blocks)
                if (b.step.assigneeId == userId)
                  Positioned(
                    left: x(b.start),
                    width: math.max(x(b.end) - x(b.start), _hourWidth / 4),
                    top: tt.tightGap,
                    bottom: tt.tightGap,
                    child: _Block(
                      block: b,
                      now: now,
                      onTap: onOpenStep == null
                          ? null
                          : () => onOpenStep!(b.step.id),
                    ),
                  ),
            ],
          ),
        ),
    ];

    final timeline = SizedBox(
      width: width,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _rowHeight / 2,
                child: Row(
                  children: [
                    for (var h = firstHour; h < lastHour; h++)
                      SizedBox(
                        width: _hourWidth,
                        child: Text(
                          planTime(
                            day.add(Duration(hours: h)),
                            l10n.localeName,
                          ),
                          style: TenturaText.withTabular(
                            TenturaText.bodySmall(tt.textMuted),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ...rowWidgets,
            ],
          ),
          if (showNow)
            Positioned(
              key: PlanPeopleMatrix.nowLineKey,
              left: x(now),
              top: 0,
              bottom: 0,
              width: _nowLineWidth,
              child: ExcludeSemantics(child: ColoredBox(color: tt.danger)),
            ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _nameColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: _rowHeight / 2),
              for (final userId in rows)
                SizedBox(
                  height: _rowHeight,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      userId == null
                          ? l10n.planMatrixUnassignedRow
                          : people.nameOf(userId, l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.bodySmall(
                        userId == null ? scheme.error : tt.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: timeline,
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, required this.now, this.onTap});

  final PlanMatrixBlock block;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final step = block.step;
    final done = step.isDone;
    final overdue = step.isOverdueAt(now);
    final background = done
        ? scheme.surfaceContainerHighest
        : scheme.secondaryContainer;
    final foreground = overdue
        ? tt.danger
        : done
        ? tt.textMuted
        : scheme.onSecondaryContainer;
    final label = [
      if (block.openStart) '…',
      if (done) '✓ ',
      if (overdue) '⏰ ',
      step.title,
      if (block.openEnd) '…',
    ].join();
    final semantics = [
      step.title,
      planStepTimeLabel(startAt: step.startAt, endAt: step.endAt, l10n: l10n),
      if (block.openStart) l10n.planMatrixOpenStart,
      if (block.openEnd) l10n.planMatrixOpenEnd,
      if (overdue) l10n.planStepOverdueSemantics(step.title),
    ].join(', ');
    final radius = BorderRadius.circular(tt.buttonRadius);
    return Semantics(
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        key: PlanPeopleMatrix.blockKey(step.id),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: overdue ? BorderSide(color: tt.danger) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(foreground).copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UntimedList extends StatelessWidget {
  const _UntimedList({
    required this.steps,
    required this.people,
    this.onOpenStep,
  });

  final List<PlanStep> steps;
  final PlanPeople people;
  final ValueChanged<String>? onOpenStep;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      key: PlanPeopleMatrix.untimedKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.planMatrixUntimedColumn,
          style: TenturaText.typeLabel(tt.textMuted),
        ),
        for (final s in steps)
          InkWell(
            onTap: onOpenStep == null ? null : () => onOpenStep!(s.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${s.isDone ? '✓ ' : ''}${s.title} · '
                  '${people.nameOf(s.assigneeId, l10n)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(
                    s.isDone ? tt.textMuted : tt.text,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
