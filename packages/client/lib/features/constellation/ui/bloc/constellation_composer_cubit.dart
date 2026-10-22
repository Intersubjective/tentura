import 'dart:async';
import 'dart:ui' show Offset;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../domain/radius_recipient_selection.dart';
import '../util/layout_geometry_adapters.dart';

/// What the full create form needs from the composer.
///
/// Both Post and Request hand off immediately with the current recipient
/// selection — no composer draft continuity. Each create screen starts its
/// own draft. Anchoring the result at the drop point is a separate, manual
/// step afterward (drag the new node, same as any other beacon on the field).
class ConstellationComposerHandoff {
  const ConstellationComposerHandoff.post({required this.recipientIds})
    : kind = BeaconKind.post,
      draftId = null,
      notes = const {};

  const ConstellationComposerHandoff.request({
    required this.recipientIds,
    this.notes = const {},
    this.draftId,
  }) : kind = BeaconKind.request;

  final BeaconKind kind;

  /// Optional draft id when continuing an existing Request draft; usually
  /// null so [BeaconCreateScreen] starts fresh.
  final String? draftId;
  final Set<String> recipientIds;
  final Map<String, String> notes;

  PageRouteInfo toRoute({
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  }) {
    if (kind == BeaconKind.post) {
      return PostCreateRoute(
        initialRecipientIds: recipientIds,
        onRecipientsChanged: onRecipientsChanged,
        onPublished: onPublished,
      );
    }
    return BeaconCreateRoute(
      draftId: draftId ?? '',
      initialRecipientIds: recipientIds,
      initialNotes: notes,
      onRecipientsChanged: onRecipientsChanged,
      onPublished: onPublished,
    );
  }
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
    this.peopleSnapshot,
    this.personName,
  }) : super(
         RadiusRecipientSelection(
           center: Offset.zero.lPoint,
           radius: kComposerMinRadius,
           positions: positions.lPoints,
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

  BeaconCreateCubit? _createCubit;

  Future<void>? _creating;

  bool _cancelled = false;

  /// Whether the circle of this session was sized to people positions, or
  /// set by the viewer; until then the first placed people size it.
  bool _sizedToPositions = false;

  BeaconKind _kind = BeaconKind.post;

  RadiusRecipientSelection get selection => state;

  BeaconKind get kind => _kind;

  /// Null until the server draft exists.
  ForwardCubit? forwardCubit;

  /// The create cubit of the current session; null before [start].
  BeaconCreateCubit? get createCubit => _createCubit;

  /// Recipients of the last sent session who were inside the circle when it
  /// was sent; empty after a cancel.
  Set<String> get sentInCircleIds => _sentInCircleIds;
  Set<String> _sentInCircleIds = const {};

  void start(BeaconKind kind, Offset scenePos) {
    _kind = kind;
    _cancelled = false;
    _sentInCircleIds = const {};
    _createCubit = createCubitFactory(kind);
    final base = state.withCenter(scenePos.lPoint);
    _sizedToPositions = base.positions.keys.any(base.eligible.contains);
    emit(
      base.withRadius(
        RadiusRecipientSelection.startRadius(
          scenePos.lPoint,
          base.positions,
          base.eligible,
        ),
      ),
    );
    if (peopleSnapshot != null) unawaited(_loadPeople(_createCubit!));
  }

  /// Re-reads who can be addressed, keeping the circle and the manual
  /// overrides. Called when the field changes while the composer is open.
  void refreshPeople() {
    final session = _createCubit;
    if (peopleSnapshot == null || session == null || _cancelled || isClosed) {
      return;
    }
    unawaited(_loadPeople(session, first: false));
  }

  /// Reads the people once. Who is reachable can change after the composer
  /// opens; [refreshPeople] picks that up.
  Future<void> _loadPeople(
    BeaconCreateCubit session, {
    bool first = true,
  }) async {
    final snapshot = await peopleSnapshot!();
    final people = (
      positions: snapshot.positions.lPoints,
      eligible: snapshot.eligible,
    );
    if (_cancelled || isClosed || !identical(session, _createCubit)) return;
    final known = state.eligible;
    // People the graph laid out only after the composer opened bring the
    // first positions; size the circle for them as for an initial snapshot.
    final firstPositions = !first && !_sizedToPositions;
    final added = {
      for (final id in people.eligible)
        if (!people.positions.containsKey(id) && !known.contains(id)) id,
    };
    if (first ||
        added.isNotEmpty ||
        !setEquals(known, people.eligible) ||
        !mapEquals(state.positions, people.positions)) {
      final center = state.center;
      final resize = first || firstPositions;
      if (resize) {
        _sizedToPositions = people.positions.keys.any(people.eligible.contains);
      }
      emit(
        RadiusRecipientSelection(
          center: center,
          radius: resize
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
  }

  void moveDraft(Offset scenePos) {
    if (_cancelled) return;
    emit(state.withCenter(scenePos.lPoint));
    _push();
  }

  void setRadius(double radius) {
    if (_cancelled) return;
    _sizedToPositions = true;
    emit(state.withRadius(radius));
    _push();
  }

  void toggleManualSelection() => emit(
    state.withManualSelectionEnabled(!state.manualSelectionEnabled),
  );

  void updatePersonPositions(Map<String, Offset> positions) {
    if (isClosed || _cancelled) return;
    final updated = {
      for (final entry in positions.entries)
        if (state.eligible.contains(entry.key) &&
            state.positions[entry.key] != entry.value.lPoint)
          entry.key: entry.value.lPoint,
    };
    if (updated.isEmpty) return;
    emit(state.withPersonPositions(updated));
    _push();
  }

  /// The composing scene has placed the people it shows at [positions]. If
  /// the circle was not sized to anyone yet, takes them and sizes the circle
  /// as for an initial snapshot; otherwise does nothing. Forward candidates
  /// absent from the normal field get their first positions only here, after
  /// the composer opened (the graph reports them at a seed point before that).
  void peoplePlaced(Map<String, Offset> positions) {
    if (isClosed || _cancelled || _createCubit == null || _sizedToPositions) {
      return;
    }
    updatePersonPositions(positions);
    if (!state.positions.keys.any(state.eligible.contains)) return;
    _sizedToPositions = true;
    emit(
      state.withRadius(
        RadiusRecipientSelection.startRadius(
          state.center,
          state.positions,
          state.eligible,
        ),
      ),
    );
    _push();
  }

  /// A person dropped inside the circle becomes a recipient, even one the
  /// viewer removed by hand before.
  void personDropped(String id) {
    if (_cancelled ||
        isClosed ||
        state.selected.contains(id) ||
        !state.eligible.contains(id) ||
        !state.isInCircle(id)) {
      return;
    }
    emit(state.addManually(id));
    _push();
  }

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

  Future<ConstellationComposerHandoff?> prepareFullFormHandoff() async =>
      fullFormHandoff();

  /// Recipient chip removals use the same persistent selection overrides.
  Future<void> toggle(String personId) async {
    if (_cancelled) return;
    emit(state.toggle(personId));
    _push();
  }

  /// First content edit; creates the draft if it does not exist yet.
  Future<void> contentChanged() => _touch();

  /// Ends the session after a send: drops the create and forward cubits so
  /// the sheet and the circle disappear.
  Future<void> finish() async {
    if (isClosed) return;
    final forward = forwardCubit;
    final create = _createCubit;
    forwardCubit = null;
    _createCubit = null;
    _sizedToPositions = false;
    _sentInCircleIds = _cancelled
        ? const {}
        : {
            for (final id in state.selected)
              if (state.isInCircle(id)) id,
          };
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

  /// Hands off immediately with the current recipient selection — no draft
  /// continuity for Post or Request. Null only before [start].
  ConstellationComposerHandoff? fullFormHandoff() {
    if (_createCubit == null) return null;
    final recipients = Set<String>.from(state.selected);
    if (_kind == BeaconKind.post) {
      return ConstellationComposerHandoff.post(recipientIds: recipients);
    }
    final forward = forwardCubit;
    return ConstellationComposerHandoff.request(
      recipientIds: forward != null
          ? {...forward.state.selectedIds}
          : recipients,
      notes: forward != null ? {...forward.state.perRecipientNotes} : const {},
      draftId: _createCubit?.state.draftId,
    );
  }

  void _push() => forwardCubit?.setSelection(state.selected);

  @override
  Future<void> close() async {
    await forwardCubit?.close();
    await _createCubit?.close();
    return super.close();
  }
}
