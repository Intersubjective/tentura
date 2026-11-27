import 'package:tentura_root/consts.dart' show kTitleMinLength;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_forward_delivery_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationPhantom extends GqlNodeBase {
  const MutationPhantom();

  PhantomCase get _case => GetIt.I<PhantomCase>();

  static final _id = InputFieldString(fieldName: 'id');
  static final _name = InputFieldString(fieldName: 'name');
  static final _keepContacts = InputFieldBool(fieldName: 'keepContacts');
  static final _clientOpId = InputFieldString(fieldName: 'clientOpId');
  static final _emoji = InputFieldString(fieldName: 'emoji');
  static final _phantomId = InputFieldString(fieldName: 'phantomId');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _note = InputFieldString(fieldName: 'note');
  static final _mergeId = InputFieldString(fieldName: 'mergeId');
  static final _userId = InputFieldString(fieldName: 'userId');
  static final _position = GraphQLFieldInput(
    'position',
    gqlInputConstellationAnchorPosition,
  );
  static final _importRows = GraphQLFieldInput(
    'rows',
    _ImportRowsType().nonNullable(),
  );
  static final _importResult = GraphQLObjectType('PhantomImportResult', null)
    ..fields.addAll([
      field(
        'created',
        GraphQLListType(
          (GraphQLObjectType('PhantomImportCreated', null)
                ..fields.addAll([
                  field('rowIndex', graphQLInt.nonNullable()),
                  field('id', graphQLString.nonNullable()),
                  field('alreadyOnTentura', graphQLBoolean),
                ]))
              .nonNullable(),
        ).nonNullable(),
      ),
      field(
        'refused',
        GraphQLListType(
          (GraphQLObjectType('PhantomImportRefused', null)
                ..fields.addAll([
                  field('rowIndex', graphQLInt.nonNullable()),
                  field('message', graphQLString.nonNullable()),
                ]))
              .nonNullable(),
        ).nonNullable(),
      ),
    ]);

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    GraphQLObjectField(
      'phantomCreate',
      graphQLString.nonNullable(),
      arguments: [_name.field, _emoji.fieldNullable, _position],
      resolve: (_, args) async => _case.create(
        ownerId: getCredentials(args).sub,
        name: _name.fromArgsNonNullable(args),
        emoji: _emoji.fromArgs(args),
        position: _readPosition(args),
      ),
    ),
    GraphQLObjectField(
      'phantomCreateBatch',
      _importResult.nonNullable(),
      description:
          'Import selected contacts. Reuse clientOpId with the same request '
          'to resume after a failure.',
      arguments: [
        _importRows,
        _keepContacts.fieldNullable,
        _clientOpId.fieldNullable,
      ],
      resolve: (_, args) async {
        final ownerId = getCredentials(args).sub;
        final clientOpId = _clientOpId.fromArgs(args)?.trim();
        if (clientOpId != null &&
            (clientOpId.isEmpty ||
                clientOpId.length > 128 ||
                clientOpId.contains('\u0000'))) {
          throw const IdWrongException(
            description: 'Invalid import operation ID',
          );
        }
        final result = await _case.createBatch(
          ownerId: ownerId,
          contacts: _readContacts(args[_importRows.name]),
          keepContacts: _keepContacts.fromArgsNonNullable(args),
          clientOpId: clientOpId,
        );
        return {
          'created': [
            for (final row in result.created)
              {
                'rowIndex': row.rowIndex,
                'id': row.id,
                'alreadyOnTentura': row.alreadyOnTentura,
              },
          ],
          'refused': [
            for (final row in result.refused)
              {
                'rowIndex': row.rowIndex,
                'message': switch (row.reason) {
                  PhantomImportRefusal.shortName =>
                    'Contact name must be at least $kTitleMinLength characters long',
                  PhantomImportRefusal.capReached =>
                    const PhantomCapReachedException().description,
                },
              },
          ],
        };
      },
    ),
    GraphQLObjectField(
      'phantomUpdate',
      graphQLBoolean.nonNullable(),
      arguments: [_id.field, _name.field, _emoji.fieldNullable],
      resolve: (_, args) async => _case.update(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        name: _name.fromArgsNonNullable(args),
        emoji: _emoji.fromArgs(args),
      ),
    ),
    GraphQLObjectField(
      'phantomDelete',
      graphQLBoolean.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.delete(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
      ),
    ),
    GraphQLObjectField(
      'phantomInviteEnsure',
      graphQLString.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.saveInvite(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        rotate: false,
      ),
    ),
    GraphQLObjectField(
      'phantomInviteRotate',
      graphQLString.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.saveInvite(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        rotate: true,
      ),
    ),
    GraphQLObjectField(
      'beaconForwardToPhantom',
      graphQLString.nonNullable(),
      arguments: [_beaconId.field, _phantomId.field, _note.fieldNullable],
      resolve: (_, args) async {
        final beaconId = _beaconId.fromArgsNonNullable(args);
        final code = await _case.forwardRequest(
          ownerId: getCredentials(args).sub,
          phantomId: _phantomId.fromArgsNonNullable(args),
          beaconId: beaconId,
          note: _note.fromArgs(args) ?? '',
        );
        return Uri(
          pathSegments: ['', 'invite', code],
          queryParameters: {'r': beaconId},
        ).toString();
      },
    ),
    GraphQLObjectField(
      'phantomLink',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _userId.field],
      resolve: (_, args) => GetIt.I<PhantomMergeCase>().link(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        userId: _userId.fromArgsNonNullable(args),
      ),
    ),
    GraphQLObjectField(
      'phantomForwardConfirm',
      graphQLBoolean.nonNullable(),
      arguments: [_id.field, _mergeId.fieldNullable],
      resolve: (_, args) => GetIt.I<PhantomForwardDeliveryCase>().confirm(
        senderId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        mergeId: _mergeId.fromArgs(args),
      ),
    ),
    GraphQLObjectField(
      'phantomUnmerge',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _mergeId.fieldNullable],
      resolve: (_, args) => GetIt.I<PhantomMergeCase>().unmerge(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        mergeId: _mergeId.fromArgs(args),
      ),
    ),
    GraphQLObjectField(
      'phantomHintDismiss',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _userId.field],
      resolve: (_, args) => _case.dismissLinkHint(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        userId: _userId.fromArgsNonNullable(args),
      ),
    ),
  ];

  static ConstellationAnchorPosition? _readPosition(
    Map<String, dynamic> args,
  ) => switch (args[_position.name]) {
    null => null,
    {
      'xUnits': final num x,
      'yUnits': final num y,
      'coordinateSpaceVersion': final int version,
    } =>
      ConstellationAnchorCase.parsePosition(
        xUnits: x.toDouble(),
        yUnits: y.toDouble(),
        coordinateSpaceVersion: version,
      ),
    _ => throw ConstellationException(
      constellationCode: ConstellationExceptionCode.invalidCoordinates,
    ),
  };

  static List<PhantomImportContact> _readContacts(Object? value) {
    if (value is! List<Object?>) {
      throw const IdWrongException(description: 'Expected a list of contacts');
    }
    return [
      for (final row in value) _readContact(row),
    ];
  }

  static PhantomImportContact _readContact(Object? row) {
    if (row is Map<String, Object?>) {
      switch ((row['name'], row['email'], row['phone'])) {
        case (final String name, final String? email, final String? phone):
          return (name: name, email: email, phone: phone);
      }
    }
    throw const IdWrongException(description: 'Invalid contact row');
  }
}

/// The executor accepts a decoded `List<dynamic>` for object input variables.
final class _ImportRowsType extends GraphQLListType<dynamic, dynamic> {
  _ImportRowsType()
    : super(
        gqlInputPhantomImportContact.nonNullable(),
      );

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}
