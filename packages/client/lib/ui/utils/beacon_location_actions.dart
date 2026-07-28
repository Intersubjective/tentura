import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_location_maps_uri.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String beaconHudLocationDisplayLabel(Beacon beacon, L10n l10n) {
  final label = beacon.addressLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return l10n.showOnMap;
}

BeaconMapsPlatform currentBeaconMapsPlatform() {
  if (kIsWeb) return BeaconMapsPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => BeaconMapsPlatform.android,
    TargetPlatform.iOS => BeaconMapsPlatform.ios,
    _ => BeaconMapsPlatform.web,
  };
}

Future<void> showBeaconLocationActions(BuildContext context, Beacon beacon) {
  final coords = beacon.coordinates;
  if (coords == null || coords.isEmpty) return Future<void>.value();

  final label = beacon.addressLabel?.trim();
  final hasAddress = label != null && label.isNotEmpty;
  final coordinatesText = '${coords.lat},${coords.long}';
  final platformRepository = GetIt.I<PlatformRepositoryPort>();

  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_outlined),
              title: const Text('Open in Maps'),
              onTap: () async {
                Navigator.pop(ctx);
                await platformRepository.launchUri(
                  beaconLocationMapsUri(
                    coordinates: coords,
                    label: label,
                    platform: currentBeaconMapsPlatform(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy address'),
              enabled: hasAddress,
              onTap: hasAddress
                  ? () async {
                      await Clipboard.setData(ClipboardData(text: label));
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.pin_drop_outlined),
              title: const Text('Copy coordinates'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: coordinatesText));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
