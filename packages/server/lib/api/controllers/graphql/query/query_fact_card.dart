import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryFactCard extends GqlNodeBase {
  QueryFactCard({BeaconFactCardCase? beaconFactCardCase})
      : _case = beaconFactCardCase ?? GetIt.I<BeaconFactCardCase>();

  final BeaconFactCardCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');
  final _factCardId = InputFieldString(fieldName: 'factCardId');
  final _before = InputFieldString(fieldName: 'before');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconFactCardList,
    beaconFactCardRevisions,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardList =>
      GraphQLObjectField(
        'BeaconFactCardList',
        GraphQLListType(gqlTypeBeaconFactCardRow.nonNullable()),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.list(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardRevisions =>
      GraphQLObjectField(
        'BeaconFactCardRevisions',
        gqlTypeBeaconFactCardRevisionsPage.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _factCardId.field,
          _before.fieldNullable,
        ],
        resolve: (_, args) async {
          final page = await _case.history(
            beaconId: _beaconIdStr.fromArgsNonNullable(args),
            factCardId: _factCardId.fromArgsNonNullable(args),
            userId: getCredentials(args).sub,
            before: _before.fromArgs(args),
          );
          return {
            'entries': [
              for (final entry in page.entries)
                switch (entry) {
                  BeaconFactHistoryRevision() => {
                    'entry': 'revision',
                    'entryKey': 'r${entry.seq.toString().padLeft(10, '0')}',
                    'seq': entry.seq,
                    'kind': entry.kind,
                    'factText': entry.factText,
                    'restoredFromSeq': entry.restoredFromSeq,
                    'actorId': entry.actorId,
                    'actorTitle': entry.actorTitle,
                    'createdAt': entry.createdAt.toUtc().toIso8601String(),
                  },
                  BeaconFactHistoryEvent() => {
                    'entry': 'event',
                    'entryKey': 'e${entry.createdAt.microsecondsSinceEpoch}',
                    'kind': entry.type,
                    'visibilityFrom': entry.visibilityFrom,
                    'visibilityTo': entry.visibilityTo,
                    'actorId': entry.actorId,
                    'actorTitle': entry.actorTitle,
                    'createdAt': entry.createdAt.toUtc().toIso8601String(),
                  },
                },
            ],
            'nextCursor': page.nextCursor,
          };
        },
      );
}
