import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class PostViewState extends StateBase {
  const PostViewState({
    required this.beacon,
    super.status = const StateIsLoading(),
  });

  final Beacon beacon;
}

/// Hosts a Post's room: loads the beacon itself and nothing Request-only.
class PostViewCubit extends Cubit<PostViewState> implements RoomHost {
  PostViewCubit({
    required String id,
    required this.myProfile,
    BeaconRepository? beaconRepository,
    UiEffectPort? effects,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(PostViewState(beacon: _emptyBeacon.copyWith(id: id)));

  static final _emptyBeacon = Beacon(
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final Profile myProfile;

  final BeaconRepository _beaconRepository;

  final UiEffectPort _effects;

  @override
  String get beaconId => state.beacon.id;

  @override
  Profile get author => state.beacon.author;

  @override
  BeaconStatus get status => state.beacon.status;

  @override
  bool get isAdmissionBlocked => false;

  @override
  bool get coordinationDeniesAdmission => false;

  @override
  RoomCapabilities get capabilities => const RoomCapabilities.post();

  @override
  Stream<void> get changes => stream.map((_) {});

  Future<void> fetch() async {
    try {
      final beacon = await _beaconRepository.fetchBeaconById(beaconId);
      if (isClosed) return;
      emit(PostViewState(beacon: beacon, status: const StateIsSuccess()));
    } on Object catch (e) {
      if (isClosed) return;
      _effects.emit(ShowError(e));
      emit(PostViewState(beacon: state.beacon, status: const StateIsSuccess()));
    }
  }
}
