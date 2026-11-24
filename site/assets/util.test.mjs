// Unit tests for the public site's pure helpers (node --test).
// These prove the safety rules the page relies on: only https links,
// allowlisted embed providers, strict uuid ids, canonical permalinks and
// human formatting. They never touch the network or a database.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  authorIdentity,
  authorLabel,
  embedUrlFor,
  formatBytes,
  initialsFor,
  isUuid,
  postPermalink,
  profilePermalink,
  providerFor,
  ratingLabel,
  relativeTime,
  safeExternalUrl,
  storagePublicUrl,
  videoIdFor,
} from './util.js';

test('safeExternalUrl only accepts absolute https URLs', () => {
  assert.equal(safeExternalUrl('https://example.com/a'), 'https://example.com/a');
  assert.equal(safeExternalUrl('http://example.com/a'), null);
  assert.equal(safeExternalUrl('javascript:alert(1)'), null);
  assert.equal(safeExternalUrl('data:text/html,<script>'), null);
  assert.equal(safeExternalUrl('/relative/path'), null);
  assert.equal(safeExternalUrl('https://user:pass@example.com/'), null);
  assert.equal(safeExternalUrl('https://example.com/a b'), null);
  assert.equal(safeExternalUrl(''), null);
  assert.equal(safeExternalUrl(null), null);
  assert.equal(safeExternalUrl(`https://example.com/${'a'.repeat(2100)}`), null);
});

test('providerFor recognises only the allowlisted video hosts', () => {
  assert.equal(providerFor('https://youtu.be/dQw4w9WgXcQ'), 'youtube');
  assert.equal(providerFor('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'youtube');
  assert.equal(providerFor('https://vimeo.com/76979871'), 'vimeo');
  assert.equal(providerFor('https://example.com/watch?v=dQw4w9WgXcQ'), null);
  assert.equal(providerFor('https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ'), null);
});

test('videoIdFor extracts ids and rejects malformed ones', () => {
  assert.equal(videoIdFor('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
  assert.equal(videoIdFor('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=4'), 'dQw4w9WgXcQ');
  assert.equal(videoIdFor('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
  assert.equal(videoIdFor('https://www.youtube.com/watch?v=short'), null);
  assert.equal(videoIdFor('https://vimeo.com/76979871'), '76979871');
  assert.equal(videoIdFor('https://vimeo.com/abc'), null);
});

test('embedUrlFor builds privacy-friendly player URLs', () => {
  assert.equal(
    embedUrlFor('https://youtu.be/dQw4w9WgXcQ'),
    'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0',
  );
  assert.equal(embedUrlFor('https://vimeo.com/76979871'), 'https://player.vimeo.com/video/76979871');
  assert.equal(embedUrlFor('https://example.com/video'), null);
  assert.equal(embedUrlFor('http://youtu.be/dQw4w9WgXcQ'), null);
});

test('isUuid is strict about the ids Postgres issues', () => {
  assert.ok(isUuid('3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab'));
  assert.equal(isUuid('3F1F8F9E-2B1A-4C3D-9E8F-0123456789AB'), false);
  assert.equal(isUuid('../../etc/passwd'), false);
  assert.equal(isUuid(''), false);
  assert.equal(isUuid(null), false);
});

test('permalinks encode the id and never double slashes', () => {
  const base = 'https://sa-mahi12.github.io/RailMate-BD';
  assert.equal(
    postPermalink(`${base}/`, '3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab'),
    `${base}/post.html?id=3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab`,
  );
  assert.equal(profilePermalink(base, 'a b'), `${base}/profile.html?id=a%20b`);
});

test('storagePublicUrl builds the public object URL', () => {
  assert.equal(
    storagePublicUrl('https://x.supabase.co/', 'uid/post/a.jpg'),
    'https://x.supabase.co/storage/v1/object/public/post-media/uid/post/a.jpg',
  );
  assert.equal(storagePublicUrl('', 'a.jpg'), null);
  assert.equal(storagePublicUrl('https://x.supabase.co', ''), null);
});

test('author helpers show public identity only', () => {
  assert.equal(authorLabel({ display_name: 'Sam', username: 'sam' }), 'Sam');
  assert.equal(authorLabel({ display_name: '  ', username: 'sam' }), '@sam');
  assert.equal(authorLabel(null), 'Traveller');
  assert.equal(authorIdentity({ display_name: 'Sam', username: 'sam' }), 'Sam · @sam');
  assert.equal(authorIdentity({ display_name: '', username: 'sam' }), '@sam');
  assert.equal(initialsFor({ display_name: 'Sam Mahi' }), 'SM');
  assert.equal(initialsFor({ username: 'sam' }), 'S');
  assert.equal(initialsFor({ display_name: 'P42 Amina (demo)' }), 'PA');
  assert.equal(initialsFor({ display_name: '(demo)' }), '?');
  assert.equal(initialsFor(null), '?');});

test('formatBytes and ratingLabel stay honest for empty data', () => {
  assert.equal(formatBytes(0), '');
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(1536), '2 KB');
  assert.equal(formatBytes(5 * 1024 * 1024), '5.0 MB');
  assert.equal(ratingLabel({ rating_count: 0 }), '');
  assert.equal(ratingLabel({ rating_count: 3, rating_average: 4.333 }), '4.3 ★ (3)');
});

test('relativeTime degrades to a date instead of guessing', () => {
  const now = Date.parse('2026-11-24T12:00:00Z');
  assert.equal(relativeTime('2026-11-24T11:59:30Z', now), 'just now');
  assert.equal(relativeTime('2026-11-24T11:45:00Z', now), '15 min ago');
  assert.equal(relativeTime('2026-11-24T09:00:00Z', now), '3 h ago');
  assert.equal(relativeTime('not a date', now), '');
});
