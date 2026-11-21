import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

/// Where a copied fact came from (plan D6): «Brought from another Request» /
/// «…Post», never the source's title or names. Shown only for copies; a tap
/// opens the source ([openFactOrigin]).
class FactOriginLine extends StatelessWidget {
  const FactOriginLine({required this.fact, super.key});

  final BeaconFactCard fact;

  @override
  Widget build(BuildContext context) {
    final kind = fact.originBeaconKind;
    if (kind == null) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => unawaited(
        openFactOrigin(context, beaconId: fact.beaconId, factCardId: fact.id),
      ),
      child: Text(
        kind == BeaconKind.post.value
            ? l10n.beaconRoomFactOriginFromPost
            : l10n.beaconRoomFactOriginFromRequest,
        style: TenturaText.status(scheme.primary),
      ),
    );
  }
}

/// Opens the source of the copied fact [factCardId] in [beaconId] (plan D7):
/// a snackbar when the viewer may not read it, otherwise the source Request
/// or Post with the source fact in focus.
Future<void> openFactOrigin(
  BuildContext context, {
  required String beaconId,
  required String factCardId,
}) async {
  final l10n = L10n.of(context)!;
  final BeaconFactOrigin origin;
  try {
    origin = await GetIt.I<BeaconThreadsCase>().factOrigin(
      beaconId: beaconId,
      factCardId: factCardId,
    );
  } on Object catch (e, st) {
    if (context.mounted) {
      showSnackBar(context, isError: true, error: e, stackTrace: st);
    }
    return;
  }
  if (!context.mounted) return;
  final sourceBeaconId = origin.beaconId;
  final sourceFactId = origin.factCardId;
  if (!origin.available || sourceBeaconId == null || sourceFactId == null) {
    showSnackBar(context, text: l10n.beaconRoomFactOriginUnavailable);
    return;
  }
  final prefix = origin.beaconKind == BeaconKind.post.value
      ? kPathPostView
      : kPathBeaconView;
  final router = context.router.root;
  // The source opens in view: close the sheets over the copy first.
  Navigator.of(context).popUntil((route) => route is! PopupRoute);
  await router.navigatePath(
    Uri(
      path: '$prefix/$sourceBeaconId',
      queryParameters: {kQueryFocusFact: sourceFactId},
    ).toString(),
  );
}
