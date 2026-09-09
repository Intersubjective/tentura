import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../domain/use_case/constellation_field_case.dart';
import '../bloc/constellation_cubit.dart';
import '../widget/constellation_body.dart';

@RoutePage()
class ConstellationScreen extends StatefulWidget implements AutoRouteWrapper {
  const ConstellationScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ConstellationCubit(
      case_: GetIt.I<ConstellationFieldCase>(),
      viewer: GetIt.I<ProfileCubit>().state.profile,
    ),
    child: this,
  );

  @override
  State<ConstellationScreen> createState() => _ConstellationScreenState();
}

class _ConstellationScreenState extends State<ConstellationScreen> {
  bool _legendExpanded = false;

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        alignment: TenturaTopBarAlignment.fullWidth,
        title: Text(
          'Constellation',
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
