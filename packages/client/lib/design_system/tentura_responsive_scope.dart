import 'package:flutter/material.dart';

import 'tentura_tokens.dart';
import 'tentura_window_class.dart';

/// Rebuilds `Theme` with `TenturaTokens` density for the current `WindowClass`.
///
/// `TextTheme` sizes are unchanged from `TenturaTheme`; [TenturaTokens.applyWindowClass]
/// updates spacing, chrome sizes, avatar/icon metrics, and `contentMaxWidth`.
class TenturaResponsiveScope extends StatelessWidget {
  const TenturaResponsiveScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.extension<TenturaTokens>();
    if (base == null) {
      return child;
    }
    final wc = context.windowClass;
    final tokens = base.applyWindowClass(wc);
    final themed = Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! TenturaTokens),
          tokens,
        ],
      ),
      child: child,
    );
    // Apply token density only. Do not cap layout width here: a centered
    // ConstrainedBox clips full-bleed shells (home rail, graph canvas) on web.
    // Screens that need a centered column use [TenturaTokens.contentMaxWidth]
    // locally (see credentials_screen.dart).
    return themed;
  }
}

/// Centers [child] when [TenturaTokens.contentMaxWidth] is set for the current
/// [WindowClass]. Use on standalone routes; not on home shell / graph canvas.
class TenturaContentColumn extends StatelessWidget {
  const TenturaContentColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxW = context.tt.contentMaxWidth;
    if (maxW == null) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}

/// Centers room-chat surfaces only after the chat panel reaches wide mode.
///
/// Unlike [TenturaContentColumn], regular-width chat stays full panel width so
/// compact and tablet layouts preserve the existing mobile-first behavior.
class TenturaChatColumn extends StatelessWidget {
  const TenturaChatColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite ||
            constraints.maxWidth < tt.chatWideWidth) {
          return child;
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tt.chatColumnMaxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

/// Master list width for expanded master–detail shells (Inbox, My Work).
double deskMasterPaneWidth(double maxWidth, TenturaTokens tt) =>
    (tt.contentMaxWidth ?? maxWidth / 2).clamp(420.0, 560.0);

/// Minimum usable width for an expanded master–detail detail pane.
const double kDeskDetailMinWidth = 360.0;

/// Comfortable ops + room pair (standalone / four-column detail).
const double kDeskOpsRoomMinPair = 720.0;

/// Tight ops + room pair when My Work list is collapsed (embedded).
const double kDeskOpsRoomMinPairTight = 560.0;

/// Horizontal chrome between expanded master list and detail pane.
double deskMasterDetailSeparatorWidth(TenturaTokens tt) =>
    tt.screenHPadding * 2 + 1;

/// @deprecated Use [deskMasterDetailSeparatorWidth].
double myWorkMasterDetailSeparatorWidth(TenturaTokens tt) =>
    deskMasterDetailSeparatorWidth(tt);

/// Detail pane width after master list and separator at [bodyWidth].
double deskDetailBudget(double bodyWidth, TenturaTokens tt) {
  final master = deskMasterPaneWidth(bodyWidth, tt);
  return bodyWidth - master - deskMasterDetailSeparatorWidth(tt);
}

/// Whether [bodyWidth] can show master list and detail side by side.
bool deskFitsMasterDetail(double bodyWidth, TenturaTokens tt) =>
    deskDetailBudget(bodyWidth, tt) >= kDeskDetailMinWidth;

/// Whether list + ops + room fit beside the rail at [bodyWidth].
bool myWorkFitsFourColumns(double bodyWidth, TenturaTokens tt) {
  final detail = deskDetailBudget(bodyWidth, tt);
  return myWorkDetailFitsOpsRoom(detail, tight: false);
}

/// Whether a detail pane can show ops and room side by side.
bool myWorkDetailFitsOpsRoom(double detailWidth, {required bool tight}) =>
    detailWidth >= (tight ? kDeskOpsRoomMinPairTight : kDeskOpsRoomMinPair);

/// Expands [child] to the full viewport width.
///
/// Kept for graph routes; a no-op when the app root is already full width.
class TenturaFullBleed extends StatelessWidget {
  const TenturaFullBleed({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
