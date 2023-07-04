part of 'new_beacon_cubit.dart';

class NewBeaconState extends StateBase {
  final bool isValid;
  final String imagePath;
  final String placeName;
  final GeoCoords? coordinates;
  final DateTimeRange? dateRange;

  const NewBeaconState({
    super.status,
    super.error,
    this.isValid = false,
    this.imagePath = '',
    this.placeName = '',
    this.coordinates,
    this.dateRange,
  });

  @override
  List<Object?> get props => [
        error,
        status,
        isValid,
        imagePath,
        dateRange,
        placeName,
        coordinates,
      ];

  bool get isNotValid => !isValid;

  NewBeaconState copyWith({
    Object? error,
    bool clearError = false,
    BlocDataStatus? status,
    String? placeName,
    GeoCoords? coordinates,
    bool clearCoordinates = false,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    String? imagePath,
    bool? isValid,
  }) =>
      NewBeaconState(
        status: status ?? this.status,
        error: clearError ? null : error ?? this.error,
        isValid: isValid ?? this.isValid,
        imagePath: imagePath ?? this.imagePath,
        dateRange: clearDateRange ? null : dateRange ?? this.dateRange,
        placeName: clearCoordinates ? '' : placeName ?? this.placeName,
        coordinates: clearCoordinates ? null : coordinates ?? this.coordinates,
      );
}
