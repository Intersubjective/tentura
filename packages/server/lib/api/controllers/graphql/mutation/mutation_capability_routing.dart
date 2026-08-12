import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCapabilityRouting extends GqlNodeBase {
  MutationCapabilityRouting({
    CapabilityRoutingCase? capabilityRoutingCase,
    InviteSeedAttestationCase? inviteSeedAttestationCase,
  })  : _capabilityRoutingCase =
            capabilityRoutingCase ?? GetIt.I<CapabilityRoutingCase>(),
        _inviteSeedAttestationCase =
            inviteSeedAttestationCase ?? GetIt.I<InviteSeedAttestationCase>();

  final CapabilityRoutingCase _capabilityRoutingCase;
  final InviteSeedAttestationCase _inviteSeedAttestationCase;

  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _subjectId = InputFieldString(fieldName: 'subjectId');
  static final _slug = InputFieldString(fieldName: 'slug');
  static final _muted = InputFieldBool(fieldName: 'muted');

  static final _slugs = GraphQLFieldInput(
    'slugs',
    GraphQLListType(graphQLString.nonNullable()),
  );

  static List<String> _slugsFromArgs(Map<String, dynamic> args) =>
      List<String>.from(args['slugs']! as List);

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        revokeAcknowledgement,
        setRoutingMute,
        seedRoutingAttestation,
        inviteSeedPromptAnswer,
        inviteSeedPromptSkip,
      ];

  GraphQLObjectField<dynamic, dynamic> get revokeAcknowledgement =>
      GraphQLObjectField(
        'revokeAcknowledgement',
        graphQLBoolean.nonNullable(),
        arguments: [_beaconId.field, _subjectId.field, _slug.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _capabilityRoutingCase.revokeAcknowledgement(
            actorId: jwt.sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
            subjectId: _subjectId.fromArgsNonNullable(args),
            slug: _slug.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get setRoutingMute =>
      GraphQLObjectField(
        'setRoutingMute',
        graphQLBoolean.nonNullable(),
        arguments: [_slug.field, _muted.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _capabilityRoutingCase.setRoutingMute(
            actorId: jwt.sub,
            slug: _slug.fromArgsNonNullable(args),
            muted: _muted.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get seedRoutingAttestation =>
      GraphQLObjectField(
        'seedRoutingAttestation',
        graphQLBoolean.nonNullable(),
        arguments: [_subjectId.field, _slugs],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final subjectId = _subjectId.fromArgsNonNullable(args);
          final slugs = _slugsFromArgs(args);
          if (slugs.isEmpty) {
            await _inviteSeedAttestationCase.withdraw(
              actorId: jwt.sub,
              subjectId: subjectId,
            );
          } else {
            await _inviteSeedAttestationCase.replaceAttestation(
              actorId: jwt.sub,
              subjectId: subjectId,
              slugs: slugs,
            );
          }
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get inviteSeedPromptAnswer =>
      GraphQLObjectField(
        'inviteSeedPromptAnswer',
        graphQLBoolean.nonNullable(),
        arguments: [_subjectId.field, _slugs],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _inviteSeedAttestationCase.answer(
            actorId: jwt.sub,
            subjectId: _subjectId.fromArgsNonNullable(args),
            slugs: _slugsFromArgs(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get inviteSeedPromptSkip =>
      GraphQLObjectField(
        'inviteSeedPromptSkip',
        graphQLBoolean.nonNullable(),
        arguments: [_subjectId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _inviteSeedAttestationCase.skip(
            actorId: jwt.sub,
            subjectId: _subjectId.fromArgsNonNullable(args),
          );
          return true;
        },
      );
}
