import 'package:tentura/consts.dart';

/// Seed-recovery WASM entry points that must survive a stale-session bootstrap.
///
/// Landing links to `/recover#/recover-seed`; a stale cookie elsewhere should
/// still bounce to landing, but not while the user is explicitly recovering.
bool isSeedRecoveryWasmEntry({
  required String pathname,
  required String hash,
}) {
  if (pathname == '/recover') {
    return true;
  }
  final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
  if (fragment == kPathRecover || fragment.startsWith('$kPathRecover/')) {
    return true;
  }
  if (pathname == kPathRecover || pathname.startsWith('$kPathRecover/')) {
    return true;
  }
  return false;
}

/// Whether a rejected session bootstrap should navigate to the landing page.
bool shouldBounceRejectedSessionToLanding({
  required String pathname,
  required String hash,
}) =>
    !isSeedRecoveryWasmEntry(pathname: pathname, hash: hash);
