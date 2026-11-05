import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/constellation_field_search_result.dart';
import '../port/constellation_field_search_port.dart';

@lazySingleton
final class ConstellationFieldSearchCase extends UseCaseBase {
  ConstellationFieldSearchCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldSearchPort _port;

  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) =>
      _port.search(query: query, context: context);
}
