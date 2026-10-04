import 'dart:async';
import 'dart:ui' show Offset;

import 'package:auto_route/auto_route.dart' show PageRouteInfo;
import 'package:flutter/foundation.dart'
    show VoidCallback, mapEquals, setEquals;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../domain/radius_recipient_selection.dart';

/// What the full create form needs from the composer.
///
/// A Request continues the same server draft the composer already made
/// (title/description typed so far carry over); a Post has no such
/// continuity — only the recipient selection matters, so it starts a fresh
/// draft in its own screen. Anchoring the result at the drop point is a
/// separate, manual step afterward (drag the new node, same as any other
/// beacon on the field).
class ConstellationComposerHandoff {
  const ConstellationComposerHandoff.post({required this.recipientIds})
    : draftId = null,
      notes = const {};

  const ConstellationComposerHandoff.request({
    required String this.draftId,
    required this.recipientIds,
    required this.notes,
  });

  /// Null for a Post hand-off.
  final String? draftId;
  final Set<String> recipientIds;
  final Map<String, String> notes;

  PageRouteInfo toRoute({
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  }) {
    final id = draftId;
    if (id == null) {
      return PostCreateRoute(
        initialRecipientIds: recipientIds,
        onRecipientsChanged: onRecipientsChanged,
        onPublished: onPublished,
      );
    }
    return BeaconCreateRoute(
      draftId: id,
      initialRecipientIds: recipientIds,
      initialNotes: notes,
      onRecipientsChanged: onRecipientsChanged,
      onPublished: onPublished,
    );
  }
}

/// How often the composer re-reads who can be addressed.
const _peopleRefresh = Duration(seconds: 4);

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
    this.peopleSnapshot,
    this.personName,
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

  final String Function(String id)? personName;

  /// Current people positions and eligibility, read when the composer starts;
  /// without it the constructor's [positions] and [eligible] stay in force.
  /// People without a position remain available for explicit selection.
  final Future<({Map<String, Offset> positions, Set<String> eligible})>
  Function()?
  peopleSnapshot;

  Timer? _peopleTimer;

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
    _peopleTimer?.cancel();
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
    if (peopleSnapshot != null) unawaited(_loadPeople(_createCubit!));
  }

  /// Reads the people now and again while the session lasts: who is reachable
  /// can change after the composer opens. Later reads keep the circle and the
  /// manual overrides.
  Future<void> _loadPeople(
    BeaconCreateCubit session, {
    bool first = true,
  }) async {
    final people = await peopleSnapshot!();
    if (_cancelled || isClosed || !identical(session, _createCubit)) return;
    final known = state.eligible;
    final added = {
      for (final id in people.eligible)
        if (!people.positions.containsKey(id) && !known.contains(id)) id,
    };
    if (first ||
        added.isNotEmpty ||
        !setEquals(known, people.eligible) ||
        !mapEquals(state.positions, people.positions)) {
      final center = state.center;
      emit(
        RadiusRecipientSelection(
          center: center,
          radius: first
              ? RadiusRecipientSelection.startRadius(
                  center,
                  people.positions,
                  people.eligible,
                )
              : state.radius,
          positions: people.positions,
          eligible: people.eligible,
          manualAdded: state.manualAdded,
          manualRemoved: state.manualRemoved,
          manualSelectionEnabled: state.manualSelectionEnabled,
        ),
      );
      _push();
    }
    _peopleTimer = Timer(
      _peopleRefresh,
      () => unawaited(_loadPeople(session, first: false)),
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

  void toggleManualSelection() => emit(
    state.withManualSelectionEnabled(!state.manualSelectionEnabled),
  );

  void toggleMapRecipient(String id) {
    if (_cancelled ||
        !state.manualSelectionEnabled ||
        !state.eligible.contains(id)) {
      return;
    }
    emit(
      state.selected.contains(id) ? state.toggle(id) : state.addManually(id),
    );
    _push();
  }

  void restoreRecipients(Set<String> ids, Map<String, String> notes) {
    if (isClosed || _cancelled) return;
    var next = state;
    for (final id in {...state.selected, ...ids}) {
      if (next.selected.contains(id) != ids.contains(id)) {
        next = next.toggle(id);
      }
    }
    emit(next);
    _push();
    for (final entry in notes.entries) {
      forwardCubit?.setRecipientNote(entry.key, entry.value);
    }
  }

  Future<ConstellationComposerHandoff?> prepareFullFormHandoff() async {
    if (_kind == BeaconKind.request) await _touch();
    return fullFormHandoff();
  }

  /// Recipient chip removals use the same persistent selection overrides.
  Future<void> toggle(String personId) async {
    if (_cancelled) return;
    emit(state.toggle(personId));
    if (_kind == BeaconKind.request) await _touch();
    _push();
  }

  /// First content edit; creates the draft if it does not exist yet.
  Future<void> contentChanged() => _touch();

  /// Ends the session after a send: drops the create and forward cubits so
  /// the sheet and the circle disappear.
  Future<void> finish() async {
    if (isClosed) return;
    _peopleTimer?.cancel();
    final forward = forwardCubit;
    final create = _createCubit;
    forwardCubit = null;
    _createCubit = null;
    emit(
      RadiusRecipientSelection(
        center: state.center,
        radius: kComposerMinRadius,
        positions: state.positions,
        eligible: state.eligible,
      ),
    );
    await forward?.close();
    await create?.close();
  }

  /// Untouched: no server call. Touched: deletes the draft, after waiting for
  /// a creation that is still in flight.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _peopleTimer?.cancel();
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

  /// A Post hands off immediately with just the current recipient selection
  /// — no draft continuity. A Request needs its server draft to already
  /// exist (first content edit or recipient change); null until then.
  ConstellationComposerHandoff? fullFormHandoff() {
    if (_kind == BeaconKind.post) {
      return ConstellationComposerHandoff.post(
        recipientIds: Set<String>.from(state.selected),
      );
    }
    final id = _createCubit?.state.draftId;
    final forward = forwardCubit;
    if (id == null || id.isEmpty || forward == null) return null;
    return ConstellationComposerHandoff.request(
      draftId: id,
      recipientIds: {...forward.state.selectedIds},
      notes: {...forward.state.perRecipientNotes},
    );
  }

  void _push() => forwardCubit?.setSelection(state.selected);

  @override
  Future<void> close() async {
    _peopleTimer?.cancel();
    await forwardCubit?.close();
    await _createCubit?.close();
    return super.close();
  }
}
