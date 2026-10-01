import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/closure_helper_cubit.dart';
import '../widget/share_flow_diagram.dart';
import '../widget/support_toggle.dart';

/// Body of the helper's «Поддержать коллег» screen — extracted for widget
/// tests (no AutoRouter). Needs a [ClosureHelperCubit] above it.
class ClosureHelperView extends StatelessWidget {
  const ClosureHelperView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ClosureHelperCubit, ClosureHelperState>(
        listenWhen: (p, c) => p.noticeTick != c.noticeTick,
        listener: (context, state) {
          final e = state.notice;
          if (e is ClosureStaleEpochException) {
            showSnackBar(context, text: L10n.of(context)!.closureHelperStale);
          } else if (e != null) {
            showSnackBar(
              context,
              text: e is LocalizableException
                  ? (L10n.of(context)!.localeName == 'ru' ? e.toRu : e.toEn)
                  : e.toString(),
              isError: true,
              error: e,
            );
          }
        },
        builder: (context, state) {
          if (state.data == null) {
            return Center(
              child: state.loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : IconButton(
                      onPressed: context.read<ClosureHelperCubit>().fetch,
                      icon: const Icon(Icons.refresh),
                    ),
            );
          }
          return _Body(state: state);
        },
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final ClosureHelperState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<ClosureHelperCubit>();
    final data = state.data!;
    final colleagues = cubit.colleagues;
    final canVote = cubit.canVote;
    final anySupport = data.mySupport.isNotEmpty;
    final fmt = DateFormat.MMMd(l10n.localeName).add_Hm();
    const gap = SizedBox(height: TenturaSpacing.section);

    String nameOf(String id) =>
        data.members
            .firstWhere(
              (m) => m.id == id,
              orElse: () => ClosureMember(id: id),
            )
            .displayName ??
        id;

    Widget person(ClosureMember m, {bool voting = false, bool first = false}) =>
        _PersonRow(
          key: ValueKey('closure.helper.person.${m.id}'),
          member: m,
          marked: data.myMarks.contains(m.id),
          onMark: (on) => cubit.setMark(m.id, on: on),
          indicator: voting && anySupport
              ? (data.mySupport.contains(m.id) ? '▲' : '▼')
              : null,
          supported: data.mySupport.contains(m.id),
          autofocus: first,
          onSupport: voting ? (on) => cubit.toggleSupport(m.id, on: on) : null,
        );

    final releasedId = state.releasedId;
    final status = switch (data.inCalcText) {
      kClosureInCalcCounted =>
        data.mySupport.isEmpty
            ? l10n.closureHelperStatusCountedNone
            : l10n.closureHelperStatusCounted(
                data.mySupport.map(nameOf).join(', '),
              ),
      kClosureInCalcDiffers => l10n.closureHelperStatusDiffers,
      _ => l10n.closureHelperStatusNone,
    };

    // ListView builds its children lazily: long rosters stay cheap.
    return ListView(
      padding: context.tt.cardPadding,
      children: [
        if (canVote) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.closureHelperHeader,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: const ValueKey('closure.helper.info'),
                tooltip: l10n.closureHelperInfoTooltip,
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showInfo(context, cubit),
              ),
            ],
          ),
          gap,
        ],
        for (final (i, m) in colleagues.indexed)
          person(m, voting: canVote, first: i == 0),
        person(cubit.author),
        const SizedBox(height: TenturaSpacing.row),
        Text(l10n.closureHelperBookmarkNote, style: theme.textTheme.bodySmall),
        if (canVote) ...[
          if (anySupport) ...[
            gap,
            Text(l10n.closureHelperLegend, style: theme.textTheme.bodySmall),
            const SizedBox(height: TenturaSpacing.tight),
            Text(
              l10n.closureHelperSupportEdgeNote,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (releasedId != null) ...[
            gap,
            Text(
              l10n.closureHelperReleased(nameOf(releasedId)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          gap,
          Text(status, style: theme.textTheme.bodyMedium),
          gap,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: cubit.done,
              child: Text(l10n.closureHelperDone),
            ),
          ),
          const SizedBox(height: TenturaSpacing.row),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _skip(context, cubit),
              child: Text(l10n.closureHelperSkip),
            ),
          ),
          Text(l10n.closureHelperSkipNote, style: theme.textTheme.bodySmall),
        ],
        gap,
        Text(
          l10n.closureHelperDeadline(fmt.format(data.closesAt.toLocal())),
          style: theme.textTheme.bodyMedium,
        ),
        if (canVote && data.earlyCloseAt != null) ...[
          const SizedBox(height: TenturaSpacing.tight),
          Text(
            l10n.closureHelperEarlyClose(
              fmt.format(data.earlyCloseAt!.toLocal()),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (canVote) ...[
          gap,
          Text(l10n.closureHelperPrivacy, style: theme.textTheme.bodySmall),
        ],
        if (data.status == kClosureStatusEvaluating) ...[
          gap,
          Text(
            l10n.closureHelperAuthorEdgeNotice,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _skip(BuildContext context, ClosureHelperCubit cubit) async {
    final l10n = L10n.of(context)!;
    final counted = state.data?.inCalcText;
    if (counted == kClosureInCalcCounted || counted == kClosureInCalcDiffers) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.closureHelperSkipConfirmTitle),
          content: Text(l10n.closureHelperSkipConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.closureHelperSkipConfirmAction),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await cubit.skip();
  }

  Future<void> _showInfo(BuildContext context, ClosureHelperCubit cubit) {
    final members = state.data!.members;
    final avatars = [
      for (final m in [cubit.author, ...members])
        Profile(
          id: m.id,
          displayName: m.displayName ?? '',
          image: m.avatarId == null
              ? null
              : ImageEntity(id: m.avatarId!, authorId: m.id),
        ),
    ];
    return showTenturaAdaptiveSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = L10n.of(sheetContext)!;
        final theme = Theme.of(sheetContext);
        return SingleChildScrollView(
          padding: sheetContext.tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShareFlowDiagram(memberCount: members.length, avatars: avatars),
              const SizedBox(height: TenturaSpacing.section),
              Text(
                l10n.closureHelperSupportEdgeNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: TenturaSpacing.section),
              Text(
                l10n.closureHelperInfoScaling,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One person: name, optional ▲/▼ marker, optional support toggle, bookmark.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.marked,
    required this.onMark,
    required this.supported,
    this.autofocus = false,
    this.indicator,
    this.onSupport,
    super.key,
  });

  final ClosureMember member;
  final bool marked;
  final ValueChanged<bool> onMark;
  final bool supported;
  final bool autofocus;
  final String? indicator;

  /// Null for people who cannot be supported (the author, non-voter view).
  final ValueChanged<bool>? onSupport;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final name = member.displayName ?? member.id;
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (indicator != null)
          Text(
            indicator!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: supported
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (onSupport != null)
          SupportToggle(
            supported: supported,
            autofocus: autofocus,
            onChanged: onSupport!,
          ),
        IconButton(
          tooltip: l10n.closureAuthorBookmarkLabel(name),
          onPressed: () => onMark(!marked),
          icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
        ),
      ],
    );
  }
}
