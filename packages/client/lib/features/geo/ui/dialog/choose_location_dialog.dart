import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:uuid/uuid.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/repository/geo_repository.dart';
import '../../data/service/google_geocoding_service.dart';
import '../../data/service/google_places_service.dart';
import '../../domain/entity/location.dart';
import '../../domain/entity/place.dart';

typedef ChooseLocationCoordinateSelector =
    Future<void> Function(
      Coordinates coordinates, {
      required bool moveCamera,
    });

typedef ChooseLocationMapBuilder =
    Widget Function(
      BuildContext context,
      Coordinates initialCenter,
      Coordinates? selected,
      ChooseLocationCoordinateSelector selectCoordinates,
    );

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

  const ChooseLocationDialog({this.center, this.mapBuilder, super.key});

  final Coordinates? center;
  final ChooseLocationMapBuilder? mapBuilder;

  @override
  State<ChooseLocationDialog> createState() => _ChooseLocationDialogState();
}

class _ChooseLocationDialogState extends State<ChooseLocationDialog> {
  static const _markerId = gmaps.MarkerId('selected-location');
  static const _uuid = Uuid();
  static const _searchDebounce = Duration(milliseconds: 300);

  final _geoRepository = GetIt.I<GeoRepository>();
  final _placesService = GetIt.I<GooglePlacesService>();
  final _geocodingService = GetIt.I<GoogleGeocodingService>();

  gmaps.GoogleMapController? _mapController;
  Timer? _debounce;
  String? _sessionToken;
  Coordinates? _selected;
  String? _addressLabel;
  List<GooglePlacePrediction> _predictions = const [];
  bool _isSearching = false;
  bool _isResolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.center;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final selected = _selected;

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          forceMaterialTransparency: true,
          foregroundColor: tt.text,
          title: Text(l10n.tapToChooseLocation),
        ),
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            widget.mapBuilder?.call(
                  context,
                  _initialCenter,
                  selected,
                  _selectCoordinates,
                ) ??
                _buildGoogleMap(selected),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                child: _LocationSearchBar(
                  predictions: _predictions,
                  isSearching: _isSearching,
                  onQueryChanged: _onQueryChanged,
                  onPredictionSelected: _selectPrediction,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _LocationConfirmBar(
          selected: selected,
          addressLabel: _addressLabel,
          isResolvingAddress: _isResolvingAddress,
          onConfirm: selected == null
              ? null
              : () => Navigator.of(context).pop(
                  Location(
                    coords: selected,
                    place: _addressLabel == null || _addressLabel!.isEmpty
                        ? null
                        : Place(locality: _addressLabel!),
                  ),
                ),
        ),
      ),
    );
  }

  Coordinates get _initialCenter =>
      widget.center ?? _geoRepository.myCoordinates ?? Coordinates.zero;

  Widget _buildGoogleMap(Coordinates? selected) {
    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: _toGoogleLatLng(_initialCenter),
        zoom: widget.center == null ? 4 : 16,
      ),
      minMaxZoomPreference: const gmaps.MinMaxZoomPreference(2, 19),
      markers: {
        if (selected != null)
          gmaps.Marker(
            markerId: _markerId,
            position: _toGoogleLatLng(selected),
            draggable: true,
            onDragEnd: (position) => _selectCoordinates(
              _fromGoogleLatLng(position),
              moveCamera: false,
            ),
          ),
      },
      zoomControlsEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        final myCoordinates = _geoRepository.myCoordinates;
        if (widget.center == null && myCoordinates != null) {
          unawaited(
            controller.animateCamera(
              gmaps.CameraUpdate.newLatLngZoom(
                _toGoogleLatLng(myCoordinates),
                14,
              ),
            ),
          );
        }
      },
      onTap: (position) => _selectCoordinates(
        _fromGoogleLatLng(position),
        moveCamera: false,
      ),
    );
  }

  String _ensureSessionToken() => _sessionToken ??= _uuid.v4();

  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _debounce?.cancel();
    if (trimmed.length < 3) {
      setState(() {
        _predictions = const [];
        _isSearching = false;
      });
      return;
    }

    final token = _ensureSessionToken();
    setState(() => _isSearching = true);
    _debounce = Timer(_searchDebounce, () async {
      try {
        final predictions = await _placesService.autocomplete(
          input: trimmed,
          sessionToken: token,
        );
        if (!mounted) return;
        setState(() {
          _predictions = predictions;
          _isSearching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _predictions = const [];
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _selectPrediction(GooglePlacePrediction prediction) async {
    final token = _ensureSessionToken();
    final place = await _placesService.details(
      placeId: prediction.placeId,
      sessionToken: token,
    );
    _sessionToken = null;
    await _setSelectedLocation(
      coordinates: place.coordinates,
      addressLabel: place.addressLabel,
      moveCamera: true,
    );
  }

  Future<void> _selectCoordinates(
    Coordinates coordinates, {
    required bool moveCamera,
  }) async {
    setState(() {
      _selected = coordinates;
      _addressLabel = null;
      _isResolvingAddress = true;
    });

    try {
      final label = await _geocodingService.reverseGeocode(coordinates);
      if (!mounted) return;
      setState(() {
        _addressLabel = label;
        _isResolvingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isResolvingAddress = false);
    }

    if (moveCamera) {
      await _moveCamera(coordinates);
    }
  }

  Future<void> _setSelectedLocation({
    required Coordinates coordinates,
    required String addressLabel,
    required bool moveCamera,
  }) async {
    setState(() {
      _selected = coordinates;
      _addressLabel = addressLabel;
      _isResolvingAddress = false;
      _predictions = const [];
    });
    if (moveCamera) {
      await _moveCamera(coordinates);
    }
  }

  Future<void> _moveCamera(Coordinates coordinates) async {
    await _mapController?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(_toGoogleLatLng(coordinates), 18),
    );
  }

  gmaps.LatLng _toGoogleLatLng(Coordinates coordinates) =>
      gmaps.LatLng(coordinates.lat, coordinates.long);

  Coordinates _fromGoogleLatLng(gmaps.LatLng coordinates) => Coordinates(
    lat: coordinates.latitude,
    long: coordinates.longitude,
  );
}

class _LocationSearchBar extends StatelessWidget {
  const _LocationSearchBar({
    required this.predictions,
    required this.isSearching,
    required this.onQueryChanged,
    required this.onPredictionSelected,
  });

  final List<GooglePlacePrediction> predictions;
  final bool isSearching;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function(GooglePlacePrediction) onPredictionSelected;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final showSuggestions = isSearching || predictions.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchBar(
          leading: const Icon(Icons.search),
          hintText: 'Search address',
          onChanged: onQueryChanged,
        ),
        if (showSuggestions) ...[
          SizedBox(height: tt.rowGap),
          Material(
            elevation: 6,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: isSearching
                ? const ListTile(
                    leading: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Searching...'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final prediction in predictions)
                        ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(prediction.description),
                          onTap: () => unawaited(
                            onPredictionSelected(prediction),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _LocationConfirmBar extends StatelessWidget {
  const _LocationConfirmBar({
    required this.selected,
    required this.addressLabel,
    required this.isResolvingAddress,
    required this.onConfirm,
  });

  final Coordinates? selected;
  final String? addressLabel;
  final bool isResolvingAddress;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final selected = this.selected;
    final label = selected == null
        ? 'Choose a location'
        : isResolvingAddress
        ? 'Resolving address...'
        : (addressLabel?.trim().isNotEmpty ?? false)
        ? addressLabel!.trim()
        : selected.toString();

    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: tt.cardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: tt.rowGap),
              FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check),
                label: const Text('Use this location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
