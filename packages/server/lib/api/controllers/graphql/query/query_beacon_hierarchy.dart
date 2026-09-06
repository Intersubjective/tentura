import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_v2_dto_maps.dart';

final class QueryBeaconHierarchy extends GqlNodeBase {
  QueryBeaconHierarchy({BeaconHierarchyRepositoryPort? hierarchyRepository})
    : _hierarchyRepository =
          hierarchyRepository ?? GetIt.I<BeaconHierarchyRepositoryPort>();

  final BeaconHierarchyRepositoryPort _hierarchyRepository;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _parentBeaconId = InputFieldString(fieldName: 'parentBeaconId');
  final _group = InputFieldString(fieldName: 'group');
  final _first = InputFieldInt(fieldName: 'first');
  final _after = InputFieldString(fieldName: 'after');
  final _sourceMessageId = InputFieldString(fieldName: 'sourceMessageId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconHierarchyCapabilities,
    beaconChildren,
    beaconParentReference,
    beaconPromotionSource,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconHierarchyCapabilities =>
      GraphQLObjectField(
        'beaconHierarchyCapabilities',
        gqlTypeBeaconHierarchyCapabilities.nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final capabilities = await _hierarchyRepository.loadCapabilities(
            parentBeaconId: _beaconId.fromArgsNonNullable(args),
            viewerId: viewerId,
          );
          return beaconHierarchyCapabilitiesToGqlMap(capabilities);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconChildren =>
      GraphQLObjectField(
        'beaconChildren',
        gqlTypeBeaconHierarchyPage.nonNullable(),
        arguments: [
          _parentBeaconId.field,
          _group.field,
          _first.fieldNullable,
          _after.fieldNullable,
        ],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final page = await _hierarchyRepository.listChildren(
            parentBeaconId: _parentBeaconId.fromArgsNonNullable(args),
            viewerId: viewerId,
            group: _parseGroup(_group.fromArgsNonNullable(args)),
            first: _resolveFirst(args),
            after: _after.fromArgs(args),
          );
          return beaconHierarchyPageToGqlMap(page);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconParentReference =>
      GraphQLObjectField(
        'beaconParentReference',
        gqlTypeBeaconParentReference.nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final reference = await _hierarchyRepository.loadParentReference(
            childBeaconId: _beaconId.fromArgsNonNullable(args),
            viewerId: viewerId,
          );
          return beaconParentReferenceToGqlMap(reference);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconPromotionSource =>
      GraphQLObjectField(
        'beaconPromotionSource',
        gqlTypeBeaconPromotionSource.nonNullable(),
        arguments: [
          _parentBeaconId.field,
          _sourceMessageId.field,
        ],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final source = await _hierarchyRepository.loadPromotionSource(
            parentBeaconId: _parentBeaconId.fromArgsNonNullable(args),
            sourceMessageId: _sourceMessageId.fromArgsNonNullable(args),
            viewerId: viewerId,
          );
          return beaconPromotionSourceToGqlMap(source);
        },
      );

  int _resolveFirst(Map<String, dynamic> args) {
    final raw = _first.fromArgs(args) ?? 20;
    if (raw < 1 || raw > 50) {
      throw UnspecifiedException(
        description: 'first must be between 1 and 50',
      );
    }
    return raw;
  }

  BeaconHierarchyChildGroup _parseGroup(String raw) => switch (raw) {
    'active' => BeaconHierarchyChildGroup.active,
    'finished' => BeaconHierarchyChildGroup.finished,
    'deleted' => BeaconHierarchyChildGroup.deleted,
    _ => throw UnspecifiedException(description: 'Invalid group: $raw'),
  };
}
