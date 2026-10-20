import 'dart:convert';
import 'dart:js_interop';

@JS('eval')
external JSAny? _evaluate(JSString source);

/// Browser-only instrumentation of the real HTTP transport. Responses and
/// persisted state still come from the server; no repository or API is faked.
/// Holding an acknowledgement makes concurrent gestures deterministic. Offline
/// mode rejects GraphQL fetches with the same TypeError as a lost connection.
final class BrowserGraphqlTransportProbe {
  void install() {
    _evaluate(
      r'''
(() => {
  if (window.__constellationTransportProbe) throw Error('probe already installed');
  const original = window.fetch;
  const state = {
    entries: [], offline: false, holdApply: false, holdTrust: false, held: [],
    clear() { this.entries.length = 0; },
    release() {
      this.holdApply = this.holdTrust = false;
      for (const resolve of this.held.splice(0)) resolve();
    },
    restore() { this.offline = false; this.release(); window.fetch = original;
                delete window.__constellationTransportProbe; }
  };
  window.__constellationTransportProbe = state;
  window.fetch = async function(input, init) {
    const request = new Request(input, init);
    if (!/\/graphql(?:\?|$)/.test(request.url)) {
      return original.call(this, input, init);
    }
    const body = await request.clone().text();
    let document;
    try { document = JSON.parse(body); }
    catch (_) { return original.call(this, input, init); }
    const entry = {
      operation: document.operationName || '', query: document.query || '',
      variables: document.variables || {}, completed: false, failed: false
    };
    state.entries.push(entry);
    try {
      if (state.offline) throw new TypeError('Failed to fetch');
      const response = await original.call(this, input, init);
      entry.status = response.status;
      entry.response = await response.clone().json();
      if ((state.holdApply && /constellationAnchorsApply/.test(entry.query)) ||
          (state.holdTrust && /userVote/.test(entry.query))) {
        await new Promise(resolve => state.held.push(resolve));
      }
      entry.completed = true;
      return response;
    } catch (error) {
      entry.failed = true;
      entry.completed = true;
      throw error;
    }
  };
})();
'''
          .toJS,
    );
  }

  void clear() => _run('clear()');
  void holdApply() => _run('holdApply = true');
  void holdTrust() => _run('holdTrust = true');
  void goOffline() => _run('offline = true');
  void restoreNetwork() => _run('offline = false');
  void release() => _run('release()');
  void dispose() => _run('restore()');

  List<Map<String, dynamic>> get entries {
    final encoded =
        _evaluate(
              'JSON.stringify(window.__constellationTransportProbe.entries)'
                  .toJS,
            )!
            as JSString;
    return (jsonDecode(encoded.toDart) as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> get applies => entries
      .where(
        (entry) =>
            (entry['query'] as String).contains('constellationAnchorsApply'),
      )
      .toList();

  List<Map<String, dynamic>> get fieldReads => entries
      .where(
        (entry) => (entry['query'] as String).contains('constellationField'),
      )
      .toList();

  List<Map<String, dynamic>> get trustWrites => entries
      .where((entry) => (entry['query'] as String).contains('userVote'))
      .toList();

  List<Map<String, dynamic>> get profileReads => entries
      .where(
        (entry) =>
            (entry['operation'] as String).contains('UserFetchById') ||
            RegExp(r'\buserById\b').hasMatch(entry['query'] as String),
      )
      .toList();

  void _run(String expression) =>
      _evaluate('window.__constellationTransportProbe.$expression'.toJS);
}
