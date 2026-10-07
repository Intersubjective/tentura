import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/favorites/data/repository/favorites_remote_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/data/repository/post_mute_repository.dart';
import 'package:tentura/features/post_view/domain/use_case/post_view_case.dart';
import 'package:tentura/features/post_view/ui/message/post_messages.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class PostViewState extends StateBase {
  const PostViewState({
    required this.beacon,
    this.summary,
    this.forwardedToMe,
    this.forwardEdges = const [],
    super.status = const StateIsLoading(),
  });

  final Beacon beacon;

  /// The viewer's conversation row for this Post (root excerpt, mute expiry).
  final PostSummary? summary;

  /// The forward that brought the Post to the viewer, if one did.
  final ForwardEdge? forwardedToMe;

  /// Every forward of the Post the viewer may see (who brought whom in).
  final List<ForwardEdge> forwardEdges;

  PostViewState copyWith({
    Beacon? beacon,
    PostSummary? summary,
    ForwardEdge? forwardedToMe,
    List<ForwardEdge>? forwardEdges,
    StateStatus? status,
  }) => PostViewState(
    beacon: beacon ?? this.beacon,
    summary: summary ?? this.summary,
    forwardedToMe: forwardedToMe ?? this.forwardedToMe,
    forwardEdges: forwardEdges ?? this.forwardEdges,
    status: status ?? this.status,
  );
}

/// Hosts a Post's room: loads the beacon itself and nothing Request-only.
class PostViewCubit extends Cubit<PostViewState> implements RoomHost {
  PostViewCubit({
    required String id,
    required this.myProfile,
    BeaconRepository? beaconRepository,
    this.postViewCase,
    UiEffectPort? effects,
    this.muteRepository,
    this.membershipRepository,
    this.favoritesRepository,
    DateTime Function()? clock,
    this.onClose,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _clock = clock ?? DateTime.now,
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(PostViewState(beacon: _emptyBeacon.copyWith(id: id))) {
    _beaconChangesSub = _beaconRepository.changes.listen((event) {
      if (event.id == beaconId &&
          (event is RepositoryEventInvalidate<Beacon> ||
              event is RepositoryEventUpdate<Beacon>)) {
        unawaited(fetch());
      }
    });
  }

  static final _emptyBeacon = Beacon(
    kind: BeaconKind.post,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final Profile myProfile;

  final BeaconRepository _beaconRepository;
  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChangesSub;

  /// Conversation row and inbound forward; built from DI on first use.
  PostViewCase? postViewCase;

  final UiEffectPort _effects;

  // Built from DI on first use, so a screen that never writes needs none.
  PostMuteRepository? muteRepository;
  PostMembershipRepository? membershipRepository;
  FavoritesRemoteRepository? favoritesRepository;

  final DateTime Function() _clock;

  /// Closes the Post's screen after delete / leave. Null for the Post's own
  /// route (it pops); a list-detail pane passes one that clears its selection.
  final void Function()? onClose;

  void _close() {
    final onClose = this.onClose;
    if (onClose == null) {
      _effects.emit(const NavigateBack());
    } else {
      onClose();
    }
  }

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

  @override
  Future<void> close() async {
    await _beaconChangesSub.cancel();
    await super.close();
  }

  Future<void> fetch() async {
    try {
      final beacon = await _beaconRepository.fetchBeaconById(beaconId);
      if (isClosed) return;
      emit(state.copyWith(beacon: beacon, status: const StateIsSuccess()));
    } on Object catch (e) {
      if (isClosed) return;
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
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
    _close();
  }

  /// Mutes the Post for [duration] from now; `null` mutes it for good.
  Future<void> mute([Duration? duration]) => _write(() async {
    await (muteRepository ??= GetIt.I<PostMuteRepository>()).setMute(
      beaconId: beaconId,
      mutedUntil: duration == null ? null : _clock().add(duration),
    );
    await _fetchExtras();
  });

  Future<void> unmute() => _write(() async {
    await (muteRepository ??= GetIt.I<PostMuteRepository>()).clearMute(
      beaconId,
    );
    await _fetchExtras();
  });

  /// Pins the Post among the viewer's conversations.
  Future<void> pin() => _write(() async {
    await (favoritesRepository ??= GetIt.I<FavoritesRemoteRepository>()).pin(
      state.beacon,
    );
    await _fetchExtras();
  });

  Future<void> unpin() => _write(() async {
    await (favoritesRepository ??= GetIt.I<FavoritesRemoteRepository>()).unpin(
      userId: myProfile.id,
      beacon: state.beacon,
    );
    await _fetchExtras();
  });

  /// Recipient-only: leaves the conversation and closes the screen; the
  /// snackbar's «Вернуть» brings the viewer back and reopens the Post.
  Future<void> leave() => _write(() async {
    final membership = membershipRepository ??=
        GetIt.I<PostMembershipRepository>();
    await membership.postLeave(beaconId);
    final id = beaconId;
    final effects = _effects;
    _close();
    _effects.emit(
      ShowMessage(
        PostLeftMessage(
          // Runs after this cubit is closed with its screen: it only uses
          // the repository and the app-wide effects port.
          onPressed: () => unawaited(() async {
            try {
              await membership.postReturn(id);
              effects.emit(NavigatePush('$kPathBeaconView/$id'));
            } on Object catch (e) {
              effects.emit(ShowError(e));
            }
          }()),
        ),
      ),
    );
  });

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (!isClosed) _effects.emit(ShowError(e));
    }
  }

  /// Conversation row and forwards are decoration: a failure leaves the
  /// room usable, so it is not surfaced.
  Future<void> _fetchExtras() async {
    PostSummary? summary;
    var summaryLoaded = false;
    List<ForwardEdge>? edges;
    try {
      final postViewCase = this.postViewCase ??= PostViewCase(
        GetIt.I<PostsRepositoryPort>(),
        GetIt.I<ForwardRepository>(),
      );
      summary = await postViewCase.summaryOf(beaconId);
      summaryLoaded = true;
      edges = await postViewCase.forwardEdges(beaconId);
    } on Object catch (_) {
      // Keep whatever was already loaded.
    }
    if (isClosed) return;
    final isAuthor = state.beacon.author.id == myProfile.id;
    emit(
      PostViewState(
        beacon: state.beacon,
        // A loaded «not in the conversation» clears a stale pin / mute.
        summary: summaryLoaded ? summary : state.summary,
        forwardedToMe: edges == null || isAuthor
            ? state.forwardedToMe
            : PostViewCase.latestTo(edges, myProfile.id),
        forwardEdges: edges ?? state.forwardEdges,
        status: state.status,
      ),
    );
  }
}
