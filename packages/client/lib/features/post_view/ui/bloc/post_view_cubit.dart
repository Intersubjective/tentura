import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/domain/use_case/post_view_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class PostViewState extends StateBase {
  const PostViewState({
    required this.beacon,
    this.summary,
    this.forwardedToMe,
    super.status = const StateIsLoading(),
  });

  final Beacon beacon;

  /// The viewer's conversation row for this Post (root excerpt, mute expiry).
  final PostSummary? summary;

  /// The forward that brought the Post to the viewer, if one did.
  final ForwardEdge? forwardedToMe;
}

/// Hosts a Post's room: loads the beacon itself and nothing Request-only.
class PostViewCubit extends Cubit<PostViewState> implements RoomHost {
  PostViewCubit({
    required String id,
    required this.myProfile,
    BeaconRepository? beaconRepository,
    this.postViewCase,
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

  /// Conversation row and inbound forward; built from DI on first use.
  PostViewCase? postViewCase;

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
      emit(
        PostViewState(
          beacon: beacon,
          summary: state.summary,
          forwardedToMe: state.forwardedToMe,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      _effects.emit(ShowError(e));
      emit(
        PostViewState(
          beacon: state.beacon,
          summary: state.summary,
          forwardedToMe: state.forwardedToMe,
          status: const StateIsSuccess(),
        ),
      );
      return;
    }
    await _fetchExtras();
  }

  /// Author-only and one-way: lets any member forward the Post.
  Future<void> allowForwarding() async {
    try {
      await _beaconRepository.openForwarding(beaconId);
    } on Object catch (e) {
      if (!isClosed) _effects.emit(ShowError(e));
      return;
    }
    await fetch();
  }

  /// Author-only: removes the Post and leaves its screen.
  Future<void> delete() async {
    try {
      await _beaconRepository.delete(beaconId);
    } on Object catch (e) {
      if (!isClosed) _effects.emit(ShowError(e));
      return;
    }
    _effects.emit(const NavigateBack());
  }

  /// Conversation row and inbound forward are decoration: a failure leaves
  /// the room usable, so it is not surfaced.
  Future<void> _fetchExtras() async {
    PostSummary? summary;
    ForwardEdge? forwardedToMe;
    try {
      final postViewCase = this.postViewCase ??= PostViewCase(
        GetIt.I<PostsRepositoryPort>(),
        GetIt.I<ForwardRepository>(),
      );
      summary = await postViewCase.summaryOf(beaconId);
      if (state.beacon.author.id != myProfile.id) {
        forwardedToMe = await postViewCase.forwardedTo(
          beaconId: beaconId,
          viewerId: myProfile.id,
        );
      }
    } on Object catch (_) {
      // Keep whatever was already loaded.
    }
    if (isClosed) return;
    emit(
      PostViewState(
        beacon: state.beacon,
        summary: summary ?? state.summary,
        forwardedToMe: forwardedToMe ?? state.forwardedToMe,
        status: state.status,
      ),
    );
  }
}
