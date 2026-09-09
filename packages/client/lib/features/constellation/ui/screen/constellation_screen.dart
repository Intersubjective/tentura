import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/constellation_field_case.dart';
import '../bloc/constellation_cubit.dart';
import '../widget/constellation_body.dart';

@RoutePage()
class ConstellationScreen extends StatefulWidget implements AutoRouteWrapper {
  const ConstellationScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    child: BlocProvider(
      create: (_) => ConstellationCubit(
        case_: GetIt.I<ConstellationFieldCase>(),
        viewer: GetIt.I<ProfileCubit>().state.profile,
      ),
      child: BlocProvider(
        create: (context) {
          final viewer = GetIt.I<ProfileCubit>().state.profile;
          return GraphPersonContextCubit(
            profileViewCase: GetIt.I<ProfileViewCase>(),
            viewerId: viewer.id,
          );
        },
        child: this,
      ),
    ),
  );

  @override
  State<ConstellationScreen> createState() => _ConstellationScreenState();
}

class _ConstellationScreenState extends State<ConstellationScreen> {
  bool _legendExpanded = false;

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        alignment: TenturaTopBarAlignment.fullWidth,
        title: Text(
          l10n.constellationTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            tooltip: _legendExpanded ? 'Close legend' : 'Open legend',
            onPressed: _toggleLegend,
            icon: Icon(_legendExpanded ? Icons.map : Icons.map_outlined),
          ),
        ],
      ),
      body: TenturaFullBleed(
        child: ConstellationBody(
          legendExpanded: _legendExpanded,
          onToggleLegend: _toggleLegend,
        ),
      ),
    );
  }
}
