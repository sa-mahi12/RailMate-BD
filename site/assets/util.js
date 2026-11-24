// Pure helpers shared by the RailMate BD public pages.
//
// No DOM, no network: everything here is deterministic and unit-tested in
// `util.test.mjs`. Anything user-generated is returned as plain text and must
// be inserted with `textContent` / `createElement`, never as HTML.

/** Only absolute https URLs are ever linked or embedded. */
export function safeExternalUrl(raw) {
  const value = String(raw ?? '').trim();
  if (!value || value.length > 2048) return null;
  if (/\s/.test(value)) return null;
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:') return null;
  if (!url.hostname) return null;
  if (url.username || url.password) return null;
  return url.toString();
}

const YOUTUBE_HOSTS = new Set([
  'youtu.be',
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtube-nocookie.com',
  'www.youtube-nocookie.com',
]);
const VIMEO_HOSTS = new Set(['vimeo.com', 'www.vimeo.com', 'player.vimeo.com']);

/** Recognised embeddable provider for a URL, or null for a plain link. */
export function providerFor(raw) {
  const safe = safeExternalUrl(raw);
  if (!safe) return null;
  const host = new URL(safe).hostname.toLowerCase();
  if (YOUTUBE_HOSTS.has(host)) return 'youtube';
  if (VIMEO_HOSTS.has(host)) return 'vimeo';
  return null;
}

/** Provider video id, or null when the URL does not yield a valid id. */
export function videoIdFor(raw) {
  const provider = providerFor(raw);
  if (!provider) return null;
  const url = new URL(safeExternalUrl(raw));
  if (provider === 'youtube') {
    if (url.hostname.toLowerCase() === 'youtu.be') {
      const id = url.pathname.split('/').filter(Boolean)[0] ?? '';
      return /^[A-Za-z0-9_-]{11}$/.test(id) ? id : null;
    }
    const v = url.searchParams.get('v') ?? '';
    if (/^[A-Za-z0-9_-]{11}$/.test(v)) return v;
    for (const segment of url.pathname.split('/')) {
      if (/^[A-Za-z0-9_-]{11}$/.test(segment)) return segment;
    }
    return null;
  }
  const segments = url.pathname.split('/').filter(Boolean).reverse();
  for (const segment of segments) {
    if (/^\d{5,12}$/.test(segment)) return segment;
  }
  return null;
}

/** Privacy-friendly embed URL for an allowlisted provider, else null. */
export function embedUrlFor(raw) {
  const provider = providerFor(raw);
  const id = videoIdFor(raw);
  if (!provider || !id) return null;
  return provider === 'youtube'
    ? `https://www.youtube-nocookie.com/embed/${id}?rel=0`
    : `https://player.vimeo.com/video/${id}`;
}

/** Strict lowercase-hex UUID check (ids issued by Postgres). */
export function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
    String(value ?? '').trim(),
  );
}

/** Canonical public post URL for a base that already ends without a slash. */
export function postPermalink(base, id) {
  return `${String(base).replace(/\/+$/, '')}/post.html?id=${encodeURIComponent(id)}`;
}

/** Canonical public profile URL. */
export function profilePermalink(base, id) {
  return `${String(base).replace(/\/+$/, '')}/profile.html?id=${encodeURIComponent(id)}`;
}

/** Human byte size (`1.4 MB`), empty for unknown sizes. */
export function formatBytes(bytes) {
  const n = Number(bytes);
  if (!Number.isFinite(n) || n <= 0) return '';
  if (n < 1024) return `${n} B`;
  const kb = n / 1024;
  if (kb < 1024) return `${Math.round(kb)} KB`;
  return `${(kb / 1024).toFixed(1)} MB`;
}

/** `24 Nov 2026, 17:05` in the reader's locale, or '' when unparseable. */
export function formatDate(value) {
  const date = new Date(String(value ?? ''));
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString(undefined, {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** Relative age for a timestamp (`3 h ago`), or '' when unparseable. */
export function relativeTime(value, now = Date.now()) {
  const date = new Date(String(value ?? ''));
  if (Number.isNaN(date.getTime())) return '';
  const seconds = Math.max(0, Math.round((now - date.getTime()) / 1000));
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} d ago`;
  return formatDate(value).split(',')[0];
}

/** Public Storage URL for one object path (bucket is world-readable). */
export function storagePublicUrl(supabaseUrl, path) {
  const base = String(supabaseUrl ?? '').replace(/\/+$/, '');
  const clean = String(path ?? '').replace(/^\/+/, '');
  if (!base || !clean) return null;
  return `${base}/storage/v1/object/public/post-media/${clean}`;
}

/** Display name for a public author card, never a private field. */
export function authorLabel(card) {
  if (!card) return 'Traveller';
  const name = String(card.display_name ?? '').trim();
  if (name) return name;
  const username = String(card.username ?? '').trim();
  return username ? `@${username}` : 'Traveller';
}

/** `Display Name · @username`, without duplicating the handle. */
export function authorIdentity(card) {
  if (!card) return 'Traveller';
  const name = String(card.display_name ?? '').trim();
  const username = String(card.username ?? '').trim();
  if (name && username) return `${name} · @${username}`;
  return authorLabel(card);
}

/**
 * Initials for the avatar bubble: the first letter of the first two words that
 * begin with a letter, so `Sam Mahi` → `SM`, `P42 Amina (demo)` → `PA` and a
 * punctuation-only name degrades to `?` instead of printing brackets.
 */
export function initialsFor(card) {
  const source = String(
    (card && (card.display_name || card.username)) || '',
  ).trim();
  if (!source) return '?';
  const letters = [];
  for (const word of source.split(/\s+/)) {
    const first = word.slice(0, 1);
    if (!/[A-Za-z\u00c0-\u024f]/.test(first)) continue;
    letters.push(first.toUpperCase());
    if (letters.length === 2) break;
  }
  return letters.length ? letters.join('') : '?';
}

/** Star average rounded to one decimal, or '' when there are no ratings. */
export function ratingLabel(stats) {
  const count = Number(stats?.rating_count ?? 0);
  const average = Number(stats?.rating_average ?? 0);
  if (!count || !Number.isFinite(average)) return '';
  return `${average.toFixed(1)} ★ (${count})`;
}
