const kLeasedJobMaxAttempts = 10;

/// Exponential backoff from the first claim, capped at 16 minutes.
Duration leasedJobRetryBackoff(int attempts) =>
    Duration(seconds: 30 * (1 << (attempts.clamp(1, 6) - 1)));
