import 'dart:async';
import 'dart:ui' show Offset;

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../domain/radius_recipient_selection.dart';

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

  void _push() => forwardCubit?.setSelection(state.selected);

  @override
  Future<void> close() async {
    await forwardCubit?.close();
    await _createCubit?.close();
    return super.close();
  }
}
