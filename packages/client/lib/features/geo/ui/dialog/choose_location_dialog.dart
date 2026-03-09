import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/repository/geo_repository.dart';
import '../../domain/entity/location.dart';

class ChooseLocationDialog extends StatefulWidget {
  static Future<Location?> show(BuildContext context, {Coordinates? center}) =>
      showAdaptiveDialog<Location>(
        context: context,
        useSafeArea: false,
        builder: (_) => ChooseLocationDialog(
          center: center == null
              ? null
              : Coordinates(lat: center.lat, long: center.long),
        ),
      );

  final Coordinates? center;

  const ChooseLocationDialog({this.center, super.key});

  @override
  State<ChooseLocationDialog> createState() => _ChooseLocationDialogState();
}

class _ChooseLocationDialogState extends State<ChooseLocationDialog> {
  final _env = GetIt.I<Env>();
  final _mapController = MapController();
  final _geoRepository = GetIt.I<GeoRepository>();

  late final _l10n = L10n.of(context)!;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        forceMaterialTransparency: true,
        foregroundColor: Colors.black,
        title: Text(_l10n.tapToChooseLocation),
      ),
      extendBodyBehindAppBar: true,
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          maxZoom: 12,
          initialZoom: widget.center == null ? 4 : 10,
          initialCenter: widget.center ?? Coordinates.zero,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: (tapPosition, point) async {
            final location = await _geoRepository.getLocationByCoords(
              Coordinates(lat: point.latitude, long: point.longitude),
            );
            if (context.mounted) Navigator.of(context).pop(location);
          },
          onMapReady: () {
            if (widget.center != null) {
              _mapController.move(widget.center!, _mapController.camera.zoom);
            } else {
              final myCoordinates = _geoRepository.myCoordinates;
              if (myCoordinates != null) {
                _mapController.move(
                  Coordinates(lat: myCoordinates.lat, long: myCoordinates.long),
                  _mapController.camera.zoom,
                );
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: _env.osmUrlTemplate,
            userAgentPackageName: kUserAgent,
            tileProvider: NetworkTileProvider(
              silenceExceptions: true,
            ),
          ),
          if (widget.center != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.center!,
                  child: const Icon(Icons.place, color: Colors.red),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
