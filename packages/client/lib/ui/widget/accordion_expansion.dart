import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_window_class.dart';

/// Scope for [AccordionExpansionTile] siblings inside [AccordionExpansionGroup].
///
/// When [accordionMode] is true, at most one tile [id] is expanded. Tiles are
/// remounted when accordion state changes (standard Material pattern); in-fold
/// scroll/list state is not preserved across sibling opens.
class AccordionExpansionScope extends InheritedWidget {
  const AccordionExpansionScope({
    required this.accordionMode,
    required this.expandedId,
    required this.onTileChanged,
    required super.child,
    super.key,
  });

  final bool accordionMode;
  final String? expandedId;
  final void Function(String id, bool expanded) onTileChanged;

  static AccordionExpansionScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AccordionExpansionScope>();
  }

  @override
  bool updateShouldNotify(AccordionExpansionScope oldWidget) {
    return accordionMode != oldWidget.accordionMode ||
        expandedId != oldWidget.expandedId;
  }
}

/// Coordinates sibling [AccordionExpansionTile]s. On compact widths (default),
/// only one section may be open at a time.
class AccordionExpansionGroup extends StatefulWidget {
  const AccordionExpansionGroup({
    required this.child,
    this.accordionMode,
    this.initialExpandedId,
    this.requestedExpandedId,
    super.key,
  });

  final Widget child;

  /// When null, uses [WindowClass.compact] from [BuildContext].
  final bool? accordionMode;

  /// Seed expansion in [initState] when [accordionMode] is true.
  final String? initialExpandedId;

  /// When this changes (e.g. deep-link focus), syncs open section in accordion mode.
  final String? requestedExpandedId;

  @override
  State<AccordionExpansionGroup> createState() => _AccordionExpansionGroupState();
}

class _AccordionExpansionGroupState extends State<AccordionExpansionGroup> {
  String? _expandedId;

  bool _resolveAccordionMode(BuildContext context) {
    return widget.accordionMode ??
        context.windowClass == WindowClass.compact;
  }

  @override
  void initState() {
    super.initState();
    _expandedId = widget.requestedExpandedId ?? widget.initialExpandedId;
  }

  @override
  void didUpdateWidget(covariant AccordionExpansionGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestedExpandedId != oldWidget.requestedExpandedId &&
        widget.requestedExpandedId != null) {
      _expandedId = widget.requestedExpandedId;
    }
  }

  void _onTileChanged(String id, bool expanded) {
    if (!_resolveAccordionMode(context)) return;
    setState(() {
      _expandedId = expanded ? id : (_expandedId == id ? null : _expandedId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accordionMode = _resolveAccordionMode(context);
    if (!accordionMode) {
      return AccordionExpansionScope(
        accordionMode: false,
        expandedId: null,
        onTileChanged: (_, _) {},
        child: widget.child,
      );
    }

    return AccordionExpansionScope(
      accordionMode: true,
      expandedId: _expandedId,
      onTileChanged: _onTileChanged,
      child: widget.child,
    );
  }
}

/// Expansion section that participates in [AccordionExpansionGroup] on compact.
class AccordionExpansionTile extends StatefulWidget {
  const AccordionExpansionTile({
    required this.id,
    required this.title,
    required this.children,
    this.leading,
    this.headerAction,
    this.initiallyExpanded = false,
    this.maintainState = true,
    super.key,
  });

  final String id;
  final Widget title;
  final List<Widget> children;
  final Widget? leading;

  /// Optional trailing control rendered before the expand chevron (e.g. filter toggle).
  final Widget? headerAction;

  /// Used only when the parent group is not in accordion mode.
  final bool initiallyExpanded;

  final bool maintainState;

  @override
  State<AccordionExpansionTile> createState() => _AccordionExpansionTileState();
}

class _AccordionExpansionTileState extends State<AccordionExpansionTile> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  Widget? _buildTrailing(ThemeData theme) {
    final action = widget.headerAction;
    if (action == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action,
        AnimatedRotation(
          turns: _expanded ? 0.5 : 0,
          duration: kThemeAnimationDuration,
          child: Icon(
            Icons.expand_more,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _onExpansionChanged(bool open, AccordionExpansionScope? scope) {
    setState(() => _expanded = open);
    if (scope?.accordionMode ?? false) {
      scope!.onTileChanged(widget.id, open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AccordionExpansionScope.maybeOf(context);
    final accordionMode = scope?.accordionMode ?? false;
    final theme = Theme.of(context);
    final trailing = _buildTrailing(theme);

    if (!accordionMode) {
      return ExpansionTile(
        leading: widget.leading,
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: widget.maintainState,
        trailing: trailing,
        onExpansionChanged: (open) => _onExpansionChanged(open, scope),
        title: widget.title,
        children: widget.children,
      );
    }

    final expanded = scope!.expandedId == widget.id;
    return ExpansionTile(
      key: ValueKey('${widget.id}-$expanded'),
      leading: widget.leading,
      initiallyExpanded: expanded,
      maintainState: widget.maintainState,
      trailing: trailing,
      onExpansionChanged: (open) => _onExpansionChanged(open, scope),
      title: widget.title,
      children: widget.children,
    );
  }
}
