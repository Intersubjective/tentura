import 'package:tentura_server/domain/port/beacon_repository_port.dart';

/// Builds an object through [create] (a constructor tear-off), handing it
/// [beaconRepository] as the named `beaconRepository` argument.
///
/// A use case that has to tell a Request from a Post needs a beacon source
/// next to its other ports. Use cases that do not load a beacon yet have no
/// such parameter: then they are built without it, so a Request-only guard
/// test loads and fails on its rejection assertion instead of on a
/// constructor mismatch.
T buildWithBeaconRepository<T>(
  Function create, {
  required List<Object?> positional,
  required Map<Symbol, Object?> named,
  required BeaconRepositoryPort beaconRepository,
}) {
  try {
    return Function.apply(create, positional, {
          ...named,
          #beaconRepository: beaconRepository,
        })
        as T;
  // A constructor without the parameter is a legitimate "not yet" outcome.
  // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return Function.apply(create, positional, named) as T;
  }
}
