import test from 'node:test';
import assert from 'node:assert/strict';
import { detectEnvironment } from '../webview.js';

const CHROME_ANDROID_UA =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const IPHONE_SAFARI_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

test('system Chrome Android UA without Telegram globals is Tier 1', () => {
  const env = detectEnvironment({ ua: CHROME_ANDROID_UA, window: {} });
  assert.equal(env.inApp, false);
  assert.equal(env.tier, 1);
});

test('Telegram Android webview is Tier 2 via TelegramWebview global', () => {
  const env = detectEnvironment({
    ua: CHROME_ANDROID_UA,
    window: { TelegramWebview: {} },
  });
  assert.equal(env.inApp, true);
  assert.equal(env.tier, 2);
});

test('Telegram iOS webview is Tier 2 via TelegramWebviewProxy globals', () => {
  const env = detectEnvironment({
    ua: IPHONE_SAFARI_UA,
    window: { TelegramWebviewProxy: {}, TelegramWebviewProxyProto: {} },
  });
  assert.equal(env.inApp, true);
  assert.equal(env.tier, 2);
  assert.equal(env.isIOS, true);
});

test('partial Telegram iOS signal without TelegramWebviewProxyProto stays Tier 1', () => {
  const env = detectEnvironment({
    ua: IPHONE_SAFARI_UA,
    window: { TelegramWebviewProxy: {} },
  });
  assert.equal(env.inApp, false);
  assert.equal(env.tier, 1);
});

test('Telegram-Android UA suffix is Tier 2 without globals', () => {
  const ua = `${CHROME_ANDROID_UA} Telegram-Android/11.2.1 (device; Android 13; SDK 33; AVERAGE)`;
  const env = detectEnvironment({ ua, window: {} });
  assert.equal(env.inApp, true);
  assert.equal(env.tier, 2);
});

test('Instagram in-app UA remains Tier 2', () => {
  const ua =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 312.0.0.0.0';
  const env = detectEnvironment({ ua, window: {} });
  assert.equal(env.inApp, true);
  assert.equal(env.tier, 2);
});
