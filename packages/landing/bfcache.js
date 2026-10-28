// #662: a back/forward-cache restore shows the page as it was left, with no
// fresh load. Run `onRestore` whenever the browser restores us from bfcache.
export function installBfcacheRefresh(win, onRestore) {
  win.addEventListener('pageshow', (event) => {
    if (event.persisted) onRestore();
  });
}
