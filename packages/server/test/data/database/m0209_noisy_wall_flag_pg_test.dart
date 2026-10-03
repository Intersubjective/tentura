@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_preference_repository.dart';

import '../../support/disposable_pg_target.dart';

/// m0209: `trust_config.noisy_wall_enabled` switches the noisy-contact wall
/// independently of ban walls. Off (the default): noisy evidence is kept but
/// the projection ignores it. See
/// `docs/plans/noisy-contact-sanctions-design.md` § 12. The wall owner's
/// `user_trust_preference` overrides the default for their own frame.
const _sender = 'Um0209sender01';
const _recipient = 'Um0209recip001';
const _other = 'Um0209other001';

const _kindHelped = 2;
const _kindNoisy = 7;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0209_NOISY_WALL_FLAG_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0209_noisy_flag',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late TrustPreferenceRepository preferences;
  Connection writer() => session.writer;

  if (reachable) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      database = openDisposablePgDatabase(target);
      preferences = TrustPreferenceRepository(database);
      for (final id in [_sender, _recipient, _other]) {
        await writer().execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
      }
    });

    setUp(() => _setFlag(writer(), enabled: false));

    tearDown(() async {
      const ids = "'$_sender', '$_recipient', '$_other'";
      await writer().execute(
        'DELETE FROM public.user_trust_preference WHERE user_id IN ($ids)',
      );
      await writer().execute(
        'DELETE FROM public.trust_publish_queue '
        'WHERE subject_user_id IN ($ids) OR object_user_id IN ($ids)',
      );
      await writer().execute(
        'DELETE FROM public.trust_evidence '
        'WHERE subject_user_id IN ($ids) OR object_user_id IN ($ids)',
      );
      await writer().execute(
        'DELETE FROM public.user_trust_edge '
        'WHERE subject IN ($ids) OR object IN ($ids)',
      );
      await writer().execute(
        'DELETE FROM public.user_block '
        'WHERE blocker_id IN ($ids) OR blocked_id IN ($ids)',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });
  }

  test(
    'migrations leave the noisy wall off and ban walls on',
    () async {
      final rows = await writer().execute('''
SELECT key, value::text FROM public.trust_config
WHERE key IN ('noisy_wall_enabled', 'wall_publish_enabled') ORDER BY key
''');
      expect(
        {for (final r in rows) r[0]! as String: r[1]! as String},
        {'noisy_wall_enabled': 'false', 'wall_publish_enabled': 'true'},
      );
    },
    skip: skipReason,
  );

  test(
    'off: three noisy observations keep their evidence but project no wall',
    () async {
      await _insertEvidence(writer(), kind: _kindNoisy, count: 3, key: 'n3');
      final fold = (await writer().execute(
        Sql.named('SELECT n_noisy FROM public.trust_fold_pair(@s, @o)'),
        parameters: {'s': _recipient, 'o': _sender},
      )).single;
      expect(fold.single! as double, closeTo(3, 1e-3));
      expect(await _projectedTarget(writer()), closeTo(0, 1e-9));
    },
    skip: skipReason,
  );

  test(
    'off: a stale trust is projected as T instead of being walled',
    () async {
      await _insertEvidence(
        writer(),
        kind: _kindHelped,
        count: 1,
        key: 'helped',
        age: const Duration(days: 250),
      );
      await _insertEvidence(writer(), kind: _kindNoisy, count: 3, key: 'n3');
      expect(await _projectedTarget(writer()), greaterThan(0.3));

      await _setFlag(writer(), enabled: true);
      expect(
        await _projectedTarget(writer()),
        closeTo(-0.1, 1e-9),
        reason: 'on: T_recent is 0, so the noisy wall replaces T (m0207)',
      );
    },
    skip: skipReason,
  );

  test(
    'off: a ban still projects -1',
    () async {
      await writer().execute(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$_recipient', '$_sender', '$_sender')",
      );
      expect(await _projectedTarget(writer()), closeTo(-1, 1e-9));
    },
    skip: skipReason,
  );

  test(
    'switching off re-projects an existing wall to 0 and queues publication',
    () async {
      await _setFlag(writer(), enabled: true);
      await _insertEvidence(writer(), kind: _kindNoisy, count: 3, key: 'n3');
      expect(await _projectedTarget(writer()), closeTo(-0.1, 1e-9));
      // The publisher acknowledged the wall.
      await writer().execute(
        Sql.named(
          'UPDATE public.user_trust_edge SET prev_sent_weight = -0.1 '
          'WHERE subject = @s AND object = @o',
        ),
        parameters: {'s': _recipient, 'o': _sender},
      );
      await writer().execute('DELETE FROM public.trust_publish_queue');

      await _setFlag(writer(), enabled: false);
      expect(await _projectedTarget(writer()), closeTo(0, 1e-9));
      final queued = await writer().execute(
        Sql.named(
          'SELECT 1 FROM public.trust_publish_queue '
          'WHERE subject_user_id = @s AND object_user_id = @o',
        ),
        parameters: {'s': _recipient, 'o': _sender},
      );
      expect(queued, hasLength(1), reason: 'MR must drop the -0.1 edge');
    },
    skip: skipReason,
  );
  group('user preference', () {
    test(
      'no row follows the default; a row overrides it for its owner only',
      () async {
        expect(await preferences.noisyWallEnabled(_recipient), isFalse);
        await _setFlag(writer(), enabled: true);
        expect(await preferences.noisyWallEnabled(_recipient), isTrue);

        await preferences.setNoisyWallEnabled(
          userId: _recipient,
          enabled: false,
        );
        expect(await preferences.noisyWallEnabled(_recipient), isFalse);
        expect(await preferences.noisyWallEnabled(_other), isTrue);
      },
      skip: skipReason,
    );

    test(
      'opting in with the default off walls existing noisy pairs at once',
      () async {
        await _insertEvidence(writer(), kind: _kindNoisy, count: 3, key: 'n3');
        expect(await _projectedTarget(writer()), closeTo(0, 1e-9));

        await preferences.setNoisyWallEnabled(
          userId: _recipient,
          enabled: true,
        );
        // Re-projected by the preference trigger, without another projection.
        expect(await _storedTarget(writer()), closeTo(-0.1, 1e-9));
        expect(await _queued(writer()), isTrue);
      },
      skip: skipReason,
    );

    test(
      'opting out with the default on removes the wall',
      () async {
        await _setFlag(writer(), enabled: true);
        await _insertEvidence(writer(), kind: _kindNoisy, count: 3, key: 'n3');
        expect(await _projectedTarget(writer()), closeTo(-0.1, 1e-9));

        await preferences.setNoisyWallEnabled(
          userId: _recipient,
          enabled: false,
        );
        expect(await _storedTarget(writer()), isNull, reason: 'target 0 with '
            'prev 0: the row is gone');
      },
      skip: skipReason,
    );

    test(
      'opting out does not lift a ban wall',
      () async {
        await writer().execute(
          'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
          "VALUES ('$_recipient', '$_sender', '$_sender')",
        );
        await preferences.setNoisyWallEnabled(
          userId: _recipient,
          enabled: false,
        );
        expect(await _projectedTarget(writer()), closeTo(-1, 1e-9));
      },
      skip: skipReason,
    );
  });
}

Future<void> _setFlag(Connection writer, {required bool enabled}) =>
    writer.execute(
      Sql.named(
        'UPDATE public.trust_config SET value = to_jsonb(@v::boolean) '
        "WHERE key = 'noisy_wall_enabled'",
      ),
      parameters: {'v': enabled},
    );

Future<void> _insertEvidence(
  Connection writer, {
  required int kind,
  required double count,
  required String key,
  Duration age = Duration.zero,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key, occurred_at
) VALUES (@id, @s, @o, @kind, @count, @key, now() - @age::interval)
'''),
  parameters: {
    'id': 'Tm0209$key',
    's': _recipient,
    'o': _sender,
    'kind': kind,
    'count': count,
    'key': 'm0209:$key',
    'age': '${age.inSeconds} seconds',
  },
);

/// Projects recipient → sender and returns `target_w` (0 when the row is
/// absent).
Future<double> _projectedTarget(Connection writer) async {
  await writer.execute(
    Sql.named('SELECT public.trust_project_pair(@s, @o)'),
    parameters: {'s': _recipient, 'o': _sender},
  );
  final rows = await writer.execute(
    Sql.named(
      'SELECT target_w FROM public.user_trust_edge '
      'WHERE subject = @s AND object = @o',
    ),
    parameters: {'s': _recipient, 'o': _sender},
  );
  return rows.isEmpty ? 0 : rows.single.single! as double;
}

/// `target_w` as stored, without projecting (null when the row is absent).
Future<double?> _storedTarget(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT target_w FROM public.user_trust_edge '
      'WHERE subject = @s AND object = @o',
    ),
    parameters: {'s': _recipient, 'o': _sender},
  );
  return rows.isEmpty ? null : rows.single.single! as double;
}

Future<bool> _queued(Connection writer) async => (await writer.execute(
  Sql.named(
    'SELECT 1 FROM public.trust_publish_queue '
    'WHERE subject_user_id = @s AND object_user_id = @o',
  ),
  parameters: {'s': _recipient, 'o': _sender},
)).isNotEmpty;
