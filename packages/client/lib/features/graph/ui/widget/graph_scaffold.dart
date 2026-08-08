import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import 'graph_app_bar_actions.dart';
import 'graph_body.dart';

/// Shared shell for graph screens: top bar actions + canvas body.
class GraphScaffold extends StatefulWidget {
  const GraphScaffold({
    required this.title,
    this.leading,
    this.progress,
    this.personContextEnabled = false,
    super.key,
  });

  final Widget title;
  final Widget? leading;
  final Widget? progress;
  final bool personContextEnabled;

  @override
  State<GraphScaffold> createState() => _GraphScaffoldState();
}

class _GraphScaffoldState extends State<GraphScaffold> {
  bool _legendExpanded = false;

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        alignment: TenturaTopBarAlignment.fullWidth,
        leading: widget.leading,
        title: widget.title,
        progress: widget.progress,
        actions: [
          GraphAppBarActions(
            legendExpanded: _legendExpanded,
            onToggleLegend: _toggleLegend,
          ),
        ],
      ),
      body: TenturaFullBleed(
        child: GraphBody(
          legendExpanded: _legendExpanded,
          onToggleLegend: _toggleLegend,
          personContextEnabled: widget.personContextEnabled,
        ),
      ),
    );
  }
}
