import test from 'node:test';
import assert from 'node:assert/strict';
import { extractUrl, canonicalize } from '../lib/urls.js';
import { hashtagsOf } from '../lib/metadata.js';

test('extracts the post URL from shared text', () => {
  assert.equal(
    extractUrl('Check this out! https://www.instagram.com/reel/Cabc123/?igsh=xyz. so good'),
    'https://www.instagram.com/reel/Cabc123/?igsh=xyz',
  );
  assert.equal(extractUrl('see https://example.com/x and https://vm.tiktok.com/ZMabc/'), 'https://vm.tiktok.com/ZMabc/');
  assert.equal(extractUrl('no links here'), null);
  assert.equal(extractUrl('https://evil.com/instagram.com/p/x'), null);
});

test('canonicalizes Instagram URLs', () => {
  assert.equal(canonicalize('https://instagram.com/p/Cabc/?igsh=1').url, 'https://www.instagram.com/p/Cabc/');
  assert.equal(canonicalize('https://www.instagram.com/reels/Cabc/').url, 'https://www.instagram.com/reel/Cabc/');
  assert.equal(canonicalize('https://www.instagram.com/someone/reel/Cabc/').url, 'https://www.instagram.com/reel/Cabc/');
  assert.equal(canonicalize('https://www.instagram.com/share/reel/BAxyz').needsResolve, true);
});

test('canonicalizes TikTok URLs', () => {
  const c = canonicalize('https://www.tiktok.com/@Some.User/video/7301234567890?is_from_webapp=1');
  assert.equal(c.url, 'https://www.tiktok.com/@Some.User/video/7301234567890');
  assert.equal(c.author, 'some.user');
  assert.equal(c.needsResolve, false);
  assert.equal(canonicalize('https://vm.tiktok.com/ZMabc/').needsResolve, true);
  assert.equal(canonicalize('https://www.tiktok.com/t/ZTabc/').needsResolve, true);
  assert.equal(canonicalize('https://example.com/'), null);
});

test('extracts hashtags', () => {
  assert.deepEqual(hashtagsOf('Easy #Pasta night #dinner #pasta'), ['pasta', 'dinner']);
});
