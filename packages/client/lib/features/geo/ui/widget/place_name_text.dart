import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordinates.dart';

import '../../data/repository/geo_repository.dart';
import '../../domain/entity/place.dart';

typedef PlaceNameFormatter = String Function(Place? place, Coordinates coords);

class PlaceNameText extends StatelessWidget {
  const PlaceNameText({
    required this.coords,
    this.style,
    this.labelForPlace,
    super.key,
  });

  final Coordinates coords;
  final TextStyle? style;

  /// When set, formats the resolved [Place] for display (default: [Place.toString]).
  final PlaceNameFormatter? labelForPlace;

  @override
  Widget build(BuildContext context) {
    final geoRepository = GetIt.I<GeoRepository>();
    final place = geoRepository.cache[coords];
    return place == null
        ? FutureBuilder(
            future: geoRepository.getLocationByCoords(coords),
            builder: (context, snapshot) => _buildText(snapshot.data?.place),
          )
        : _buildText(place);
  }

  String _format(Place? place) =>
      labelForPlace?.call(place, coords) ??
      place?.toString() ??
      coords.toString();

  Text _buildText(Place? place) => Text(
        _format(place),
        maxLines: 1,
        textAlign: TextAlign.left,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
}
