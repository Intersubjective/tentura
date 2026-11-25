import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';

/// Gives owner surfaces the same Field snapshot and refresh lifecycle as the map.
class PhantomFieldBuilder extends StatefulWidget {
  const PhantomFieldBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, ConstellationField? field)
  builder;

  @override
  State<PhantomFieldBuilder> createState() => _PhantomFieldBuilderState();
}

class _PhantomFieldBuilderState extends State<PhantomFieldBuilder> {
  ConstellationFieldStoreCase? _store;
  StoreLease? _lease;

  @override
  void initState() {
    super.initState();
    final store = GetIt.I.maybeGet<ConstellationFieldStoreCase>();
    if (store == null || !store.phantomsEnabled) return;
    _store = store;
    _lease = store.lease();
    if (store.current.field == null) {
      unawaited(store.requestRefresh(ConstellationRefreshReason.resume));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lease?.setVisible(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _lease?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) return widget.builder(context, null);
    return StreamBuilder<ConstellationFieldStoreState>(
      stream: store.changes,
      builder: (context, _) => widget.builder(context, store.current.field),
    );
  }
}
