import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart'
    show kLazyWriteAckTimeout;
import 'package:tentura/features/like/domain/exception.dart';
import 'package:tentura/features/like/domain/port/like_write_port.dart';

final class GraphTrustRevert {
  const GraphTrustRevert({
    required this.profile,
    required this.acknowledgedAmount,
    required this.intendedAmount,
  });

  final Profile profile;
  String get peerId => profile.id;
  final int acknowledgedAmount;
  final int intendedAmount;
}

/// Account-owned, latest-wins trust writes. Screen disposal does not cancel them.
@singleton
final class GraphTrustWriteCase extends UseCaseBase {
  GraphTrustWriteCase(
    this._likes,
    this._wakeUp,
    ConstellationAccountPort account, {
    required super.env,
    required super.logger,
  }) {
    _accountSubscription = account.currentAccountChanges.distinct().listen((
      id,
    ) {
      if (_accountId == id) return;
      _reset();
      _accountId = id;
    });
  }

  final LikeWritePort _likes;
  final WakeUpPort _wakeUp;
  final _random = Random();
  final _peers = <String, _TrustSlot>{};
  final _reverts = StreamController<GraphTrustRevert>.broadcast();
  final _resets = StreamController<Profile>.broadcast();
  final _notices = StreamController<LazyWriteNotice>.broadcast();
  late final StreamSubscription<String> _accountSubscription;
  String _accountId = '';
  bool _disposed = false;
  bool _noticeRaised = false;

  Stream<GraphTrustRevert> get reverts => _reverts.stream;

  /// Peers whose unacknowledged trust was dropped by an account change, with
  /// the last acknowledged value restored.
  Stream<Profile> get resets => _resets.stream;

  Stream<LazyWriteNotice> get lazyWriteNotices => _notices.stream;

  Profile setTrust(Profile peer, {required bool add}) {
    final amount = add ? 1 : 0;
    if (_disposed || _accountId.isEmpty) return peer;
    final supersedesRejection = _peers[peer.id]?.rejection != null;
    final slot = _peers.putIfAbsent(peer.id, () => _TrustSlot(peer))
      ..profile = peer
      ..desired = amount
      ..rejection = null;
    if (!slot.active) _start(slot, force: !supersedesRejection);
    return peer.copyWith(myVote: amount);
  }

  /// A Retry action belongs to its rejected intent and account, even if the
  /// panel has since selected someone else.
  Profile? retry(GraphTrustRevert revert) {
    if (!isCurrentRevert(revert)) return null;
    _peers[revert.peerId]!.rejection = null;
    return setTrust(
      revert.profile.copyWith(myVote: revert.acknowledgedAmount),
      add: revert.intendedAmount == 1,
    );
  }

  bool isCurrentRevert(GraphTrustRevert revert) =>
      identical(_peers[revert.peerId]?.rejection, revert);

  /// Preserve a local trust value when a selection read completes mid-write.
  Profile overlay(Profile peer, {bool authoritative = false}) {
    final slot = _peers[peer.id];
    // Keep acknowledgements over stale graph snapshots, but allow a later
    // profile read to reflect trust changes made through the profile screen.
    if (authoritative &&
        slot != null &&
        !slot.active &&
        slot.rejection == null) {
      _peers.remove(peer.id);
      return peer;
    }
    return slot == null
        ? peer
        : peer.copyWith(myVote: slot.active ? slot.desired : slot.acknowledged);
  }

  bool _isLive(_TrustSlot slot) =>
      !_disposed && identical(_peers[slot.profile.id], slot);

  void _start(_TrustSlot slot, {bool force = false}) {
    if (!force && slot.desired == slot.acknowledged) {
      _settled();
      return;
    }
    slot.active = true;
    slot.inFlight = slot.desired;
    slot.attempts = 0;
    slot.overdue = _wakeUp.schedule(kLazyWriteAckTimeout, () {
      if (!_isLive(slot) || !slot.active || _noticeRaised) return;
      _noticeRaised = true;
      _notices.add(const LazyWriteNotice());
    });
    unawaited(_send(slot));
  }

  Future<void> _send(_TrustSlot slot) async {
    slot.attempts++;
    try {
      await _likes.setLike(slot.profile, amount: slot.inFlight);
      if (!_isLive(slot)) return;
      slot.acknowledged = slot.inFlight;
      slot.active = false;
      slot.overdue?.cancel();
      _start(slot);
    } on Object catch (error, stackTrace) {
      if (!_isLive(slot)) return;
      if (error is LikeException || slot.attempts >= 3) {
        slot.active = false;
        slot.overdue?.cancel();
        final intended = slot.desired;
        slot.desired = slot.acknowledged;
        final revert = GraphTrustRevert(
          profile: slot.profile,
          acknowledgedAmount: slot.acknowledged,
          intendedAmount: intended,
        );
        slot.rejection = revert;
        _reverts.add(revert);
        _settled();
      } else {
        final base = min(30000, 1000 * (1 << (slot.attempts - 1)));
        final half = base ~/ 2;
        slot.retry = _wakeUp.schedule(
          Duration(milliseconds: half + _random.nextInt(half) + 1),
          () {
            if (_isLive(slot)) unawaited(_send(slot));
          },
        );
      }
      logger.warning('Graph trust write failed', error, stackTrace);
    }
  }

  void _settled() {
    if (_peers.values.every((slot) => !slot.active)) _noticeRaised = false;
  }

  void _reset() {
    for (final slot in _peers.values) {
      slot.overdue?.cancel();
      slot.retry?.cancel();
      if (slot.desired != slot.acknowledged) {
        _resets.add(slot.profile.copyWith(myVote: slot.acknowledged));
      }
    }
    _peers.clear();
    _noticeRaised = false;
  }

  @disposeMethod
  Future<void> dispose() async {
    _disposed = true;
    _reset();
    await _accountSubscription.cancel();
    await _reverts.close();
    await _resets.close();
    await _notices.close();
  }
}

final class _TrustSlot {
  _TrustSlot(this.profile)
    : acknowledged = profile.myVote,
      desired = profile.myVote;

  Profile profile;
  int acknowledged;
  int desired;
  int inFlight = 0;
  int attempts = 0;
  bool active = false;
  WakeUpHandle? overdue;
  WakeUpHandle? retry;
  GraphTrustRevert? rejection;
}
