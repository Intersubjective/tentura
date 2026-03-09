import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../exception/user_input_exception.dart';
import 'identifiable.dart';
import 'profile.dart';

part 'polling.freezed.dart';

@freezed
abstract class Polling extends Identifiable with _$Polling {
  static const questionMaxLength = 256;

  static const questionMinLength = 8;

  static const variantMaxLength = 64;

  static const variantMinLength = 2;

  static void questionValidator(String value) {
    if (value.length < questionMinLength) {
      throw const PollingQuestionTooShortException();
    }
  }

  static void variantValidator(String value) {
    if (value.length < variantMinLength) {
      throw const PollingVariantTooShortException();
    }
  }

  const factory Polling({
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String id,
    @Default('') String question,
    @Default(true) bool isEnabled,
    @Default(Profile()) Profile author,
    @Default({}) Set<String> selection,
    @Default({}) Map<String, String> variants,
  }) = _Polling;

  const Polling._();

  bool get isEmpty => question.isEmpty && variants.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool get hasVariants => variants.isNotEmpty;
  bool get hasNoVariants => !hasVariants;

  bool get hasChoice => selection.isNotEmpty;
  bool get hasNoChoice => !hasChoice;

  void validate() {
    questionValidator(question);
    if (variants.length < 2) {
      throw const PollingTooFewVariantsException();
    }
    variants.values.forEach(variantValidator);
  }
}
