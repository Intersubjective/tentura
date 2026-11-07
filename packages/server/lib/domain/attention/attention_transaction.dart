import 'package:tentura_server/domain/attention/attention_models.dart';

/// Handle for recording attention intents inside the unit of work opened by
/// `TransactionalAttentionCase`.
///
/// The only implementation is created by `TransactionalAttentionCase`; this
/// interface lives in the attention domain so entities and ports can name the
/// type without depending on the use case.
// ignore: one_member_abstracts -- a type entities and ports can name; implemented privately by the use case
abstract interface class AttentionTransaction {
  Future<void> record(AttentionDispatchIntent intent);
}
