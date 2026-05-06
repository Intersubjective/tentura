/// Room @mention handle: 3–30 chars, lowercase letters, digits, underscore.
const kUserHandleMinLength = 3;

const kUserHandleMaxLength = 30;

/// Normalized (lowercase) pattern for validation after trim.
final RegExp kUserHandleRegExp = RegExp(
  '^[a-z0-9_]{$kUserHandleMinLength,$kUserHandleMaxLength}\$',
);

bool isValidUserHandleFormat(String trimmedLowercase) =>
    kUserHandleRegExp.hasMatch(trimmedLowercase);
