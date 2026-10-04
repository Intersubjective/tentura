import 'dart:async';
import 'dart:ui' show Offset;

import 'package:auto_route/auto_route.dart' show PageRouteInfo;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_layout.dart';
import '../../domain/radius_recipient_selection.dart';
import '../../domain/use_case/constellation_anchor_case.dart';

/// What the full create form needs to continue the composer's draft.
class ConstellationComposerHandoff {
  const ConstellationComposerHandoff({
    required this.draftId,
    required this.recipientIds,
    required this.notes,
  });

  final String draftId;
  final Set<String> recipientIds;
  final Map<String, String> notes;

  PageRouteInfo toRoute() => BeaconCreateRoute(
    draftId: draftId,
    initialRecipientIds: recipientIds,
    initialNotes: notes,
  );
}

/// Result of sending from the composer.
class ConstellationComposerSendOutcome {
  const ConstellationComposerSendOutcome({
    required this.published,
    required this.anchored,
    this.beaconId,
  });

  final bool published;
  final bool anchored;
  final String? beaconId;
}

/// Owns the graph composer: recipient selection, the draft position and the
/// lazily created server draft with its embedded [ForwardCubit].
///
/// The server draft is created on the first content edit or recipient change.
/// The state is the current [RadiusRecipientSelection].
class ConstellationComposerCubit extends Cubit<RadiusRecipientSelection> {
  ConstellationComposerCubit({
    required Map<String, Offset> positions,
    required Set<String> eligible,
    required this.createCubitFactory,
    required this.forwardCubitFactory,
  }) : super(
         RadiusRecipientSelection(
           center: Offset.zero,
           radius: kComposerMinRadius,
           positions: positions,
           eligible: eligible,
         ),
       );

  final BeaconCreateCubit Function(BeaconKind kind) createCubitFactory;

  final ForwardCubit Function(String beaconId) forwardCubitFactory;

  BeaconCreateCubit? _createCubit;

  Future<void>? _creating;

  bool _cancelled = false;

  BeaconKind _kind = BeaconKind.post;

  RadiusRecipientSelection get selection => state;

  BeaconKind get kind => _kind;

  /// Null until the server draft exists.
  ForwardCubit? forwardCubit;

  /// The create cubit of the current session; null before [start].
  BeaconCreateCubit? get createCubit => _createCubit;

  void start(BeaconKind kind, Offset scenePos) {
    _kind = kind;
    _cancelled = false;
    _createCubit = createCubitFactory(kind);
    final base = state.withCenter(scenePos);
    emit(
      base.withRadius(
        RadiusRecipientSelection.startRadius(
          scenePos,
          base.positions,
          base.eligible,
        ),
      ),
    );
  }

  void moveDraft(Offset scenePos) {
    if (_cancelled) return;
    emit(state.withCenter(scenePos));
    _push();
  }

  void setRadius(double radius) {
    if (_cancelled) return;
    emit(state.withRadius(radius));
    _push();
  }

  /// Graph and list toggles both come through here.
  Future<void> toggle(String personId) async {
    if (_cancelled) return;
    emit(state.toggle(personId));
    await _touch();
    _push();
  }

  /// First content edit; creates the draft if it does not exist yet.
  Future<void> contentChanged() => _touch();

  /// Untouched: no server call. Touched: deletes the draft, after waiting for
  /// a creation that is still in flight.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _creating;
    final create = _createCubit;
    if (create != null && (create.state.draftId?.isNotEmpty ?? false)) {
      await create.deleteDraft();
    }
  }

  Future<void> _touch() async {
    if (_cancelled || _createCubit == null) return;
    final inFlight = _creating ??= _createDraft().whenComplete(
      () => _creating = null,
    );
    await inFlight;
  }

  Future<void> _createDraft() async {
    final id = await _createCubit!.ensureDraft(
      context: '',
      showMessage: false,
      quiet: true,
    );
    if (_cancelled || isClosed || id == null || forwardCubit != null) return;
    forwardCubit = forwardCubitFactory(id);
    _push();
  }

  /// Null until the server draft exists.
  ConstellationComposerHandoff? fullFormHandoff() {
    final id = _createCubit?.state.draftId;
    final forward = forwardCubit;
    if (id == null || id.isEmpty || forward == null) return null;
    return ConstellationComposerHandoff(
      draftId: id,
      recipientIds: {...forward.state.selectedIds},
      notes: {...forward.state.perRecipientNotes},
    );
  }

  /// Publishes the Post, then anchors it at the draft point. An anchor failure
  /// is shown as a snackbar; the Post stays published.
  Future<ConstellationComposerSendOutcome> sendPost({
    required String body,
    required ConstellationAnchorCase anchorCase,
    required int generation,
  }) async {
    final create = _createCubit;
    final forward = forwardCubit;
    if (create == null || forward == null) {
      return const ConstellationComposerSendOutcome(
        published: false,
        anchored: false,
      );
    }
    final published = await create.publishPost(
      body: body,
      mentions: const [],
      forwardCubit: forward,
      forwardPolicy: BeaconForwardPolicyValue.closed,
      attachments: const [],
    );
    return _anchorPublished(published, anchorCase, generation);
  }

  /// Sends the Request to the selected recipients, then anchors it.
  Future<ConstellationComposerSendOutcome> sendRequest({
    required ConstellationAnchorCase anchorCase,
    required int generation,
  }) async {
    final create = _createCubit;
    final forward = forwardCubit;
    if (create == null || forward == null) {
      return const ConstellationComposerSendOutcome(
        published: false,
        anchored: false,
      );
    }
    final outcome = await create.sendRequest(
      context: '',
      forwardCubit: forward,
    );
    return _anchorPublished(outcome != null, anchorCase, generation);
  }

  Future<ConstellationComposerSendOutcome> _anchorPublished(
    bool published,
    ConstellationAnchorCase anchorCase,
    int generation,
  ) async {
    final create = _createCubit!;
    final id = create.state.draftId;
    if (!published || id == null || id.isEmpty) {
      return const ConstellationComposerSendOutcome(
        published: false,
        anchored: false,
      );
    }
    try {
      final result = await anchorCase.upsert(
        target: ConstellationAnchorTarget.beacon(id),
        position: constellationPointToV1Anchor(
          (x: state.center.dx, y: state.center.dy),
        ),
        generation: generation,
      );
      final ok = result.kind == ConstellationAnchorWriteOutcomeKind.succeeded;
      if (!ok) {
        create.reportError(result.failureMessage ?? 'anchor failed');
      }
      return ConstellationComposerSendOutcome(
        published: true,
        anchored: ok,
        beaconId: id,
      );
    } on Object catch (e) {
      create.reportError(e);
      return ConstellationComposerSendOutcome(
        published: true,
        anchored: false,
        beaconId: id,
      );
    }
  }

  void _push() => forwardCubit?.setSelection(state.selected);

  @override
  Future<void> close() async {
    await forwardCubit?.close();
    await _createCubit?.close();
    return super.close();
  }
}
