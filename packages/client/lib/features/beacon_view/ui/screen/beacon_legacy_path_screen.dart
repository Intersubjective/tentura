import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// Legacy route stub — `/beacon/:id` (without `/view`) redirects in [RootRouter].
@RoutePage()
class BeaconLegacyPathScreen extends StatelessWidget {
  const BeaconLegacyPathScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
