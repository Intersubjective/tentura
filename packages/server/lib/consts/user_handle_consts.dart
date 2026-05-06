/// Room @mention handle: 5–30 chars, lowercase letters, digits, underscore.
const kUserHandleMinLength = 5;

const kUserHandleMaxLength = 30;

/// Normalized (lowercase) pattern for validation after trim.
final RegExp kUserHandleRegExp = RegExp(
  r'^[a-z0-9_]{5,30}$',
);

bool isValidUserHandleFormat(String trimmedLowercase) =>
    kUserHandleRegExp.hasMatch(trimmedLowercase);
