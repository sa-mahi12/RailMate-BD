// RailMate BD public site — live Journey Board on GitHub Pages.
//
// Data comes from the hosted Supabase REST API with the public anon key
// (RLS-protected, read-only for this viewer). Nothing is mocked: every card
// on the page is a real row. Writes (posting, reacting, rating, commenting)
// happen in the Android app; this page is the permanent, shareable view.
//
// Safety rules enforced here:
//   * user text is inserted with textContent, never innerHTML;
//   * links/embeds must pass util.safeExternalUrl (https, allowlisted host);
//   * provider embeds load only after an explicit click, in a sandboxed frame.

import {
  authorIdentity,
  authorLabel,
  embedUrlFor,
  formatBytes,
  formatDate,
  initialsFor,
  isUuid,
  postPermalink,
  profilePermalink,
  providerFor,
  ratingLabel,
  relativeTime,
  safeExternalUrl,
  storagePublicUrl,
} from './util.js';

const cfg = window.RAILMATE_CONFIG || {};
const SUPABASE_URL = String(cfg.SUPABASE_URL || '').replace(/\/+$/, '');
const SUPABASE_ANON_KEY = String(cfg.SUPABASE_ANON_KEY || '');
const SITE_BASE = String(cfg.SITE_BASE || location.origin + location.pathname.replace(/[^/]*$/, '')).replace(/\/+$/, '');
const APP_SCHEME = 'railmatebd';
const POLL_MS = 20000;

const state = {
  timer: null,
  authors: new Map(),
  stats: new Map(),
};

// ---------------------------------------------------------------- utilities

/** Creates an element with attributes and children (text stays text). */
function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = String(value);
    else if (key === 'dataset') Object.assign(node.dataset, value);
    else node.setAttribute(key, String(value));
  }
  for (const child of [].concat(children)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

function status(message, { error = false, retry = null } = {}) {
  const box = document.getElementById('status');
  if (!box) return;
  clear(box);
  box.className = `status${error ? ' error' : ''}`;
  box.hidden = false;
  box.append(document.createTextNode(message));
  if (retry) {
    box.append(
      el('button', { class: 'retry', type: 'button', text: 'Retry', onclick: retry }),
    );
  }
}

function hideStatus() {
  const box = document.getElementById('status');
  if (box) box.hidden = true;
}

function requireConfig() {
  if (SUPABASE_URL && SUPABASE_ANON_KEY) return true;
  status(
    'This page is not configured: assets/config.js is missing the public Supabase URL and anon key. The deploy workflow generates it from repository variables.',
    { error: true },
  );
  return false;
}

/** One PostgREST read. Throws a plain Error the caller renders honestly. */
async function rest(table, { select = '*', filters = {}, order = null, limit = null, single = false } = {}) {
  const params = new URLSearchParams({ select });
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null && value !== '') params.set(key, String(value));
  }
  if (order) params.set('order', order);
  if (limit) params.set('limit', String(limit));
  const url = `${SUPABASE_URL}/rest/v1/${table}?${params.toString()}`;
  const res = await fetch(url, {
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      accept: 'application/json',
    },
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`${table}: HTTP ${res.status} ${detail.slice(0, 160)}`);
  }
  const data = await res.json();
  if (single) return Array.isArray(data) ? data[0] ?? null : data;
  return Array.isArray(data) ? data : [];
}

function quoteIn(values) {
  return `in.(${values.map((v) => `"${String(v).replace(/"/g, '')}"`).join(',')})`;
}

function appLink(path) {
  return `${APP_SCHEME}://${path}`;
}

// ----------------------------------------------------------------- fetching

async function loadAuthors(ids) {
  const unique = [...new Set(ids.filter((id) => isUuid(id)))].filter((id) => !state.authors.has(id));
  if (!unique.length) return;
  const rows = await rest('public_profile_cards', {
    select: 'id,username,display_name,joined_at,post_count',
    filters: { id: quoteIn(unique) },
  });
  for (const row of rows) state.authors.set(row.id, row);
}

async function loadStats(postIds) {
  const unique = [...new Set(postIds.filter((id) => isUuid(id)))];
  if (!unique.length) return;
  const rows = await rest('public_post_stats', {
    select: 'post_id,like_count,dislike_count,rating_count,rating_average,comment_count',
    filters: { post_id: quoteIn(unique) },
  });
  for (const row of rows) state.stats.set(row.post_id, row);
}

// ---------------------------------------------------------------- rendering

function imageTile(url, name) {
  const link = el('a', { href: url, target: '_blank', rel: 'noopener noreferrer', title: name });
  const img = el('img', { src: url, alt: name, loading: 'lazy', decoding: 'async' });
  img.addEventListener('error', () => {
    link.replaceWith(
      el('div', { class: 'file-card' }, [
        el('div', { class: 'meta' }, [
          el('strong', { text: name }),
          el('small', { text: 'Photo unavailable' }),
        ]),
      ]),
    );
  });
  link.append(img);
  return link;
}

function attachmentNode(att) {
  const kind = String(att.kind || 'file');
  if (kind === 'link') {
    const raw = safeExternalUrl(att.external_url);
    if (!raw) {
      return el('div', { class: 'link-card', text: 'Link unavailable' });
    }
    const embed = embedUrlFor(raw);
    const host = new URL(raw).hostname.replace(/^www\./, '');
    if (embed) {
      const frameHost = el('div', { class: 'embed' });
      const button = el('button', {
        class: 'load-embed',
        type: 'button',
        text: `Play ${providerFor(raw)} video (loads the provider player)`,
      });
      button.addEventListener('click', () => {
        clear(frameHost);
        frameHost.append(
          el('iframe', {
            src: embed,
            title: 'Embedded video',
            loading: 'lazy',
            allow: 'accelerometer; encrypted-media; gyroscope; picture-in-picture',
            allowfullscreen: 'true',
            referrerpolicy: 'strict-origin-when-cross-origin',
            sandbox: 'allow-scripts allow-same-origin allow-presentation allow-popups',
          }),
          el('a', { class: 'embed-note', href: raw, target: '_blank', rel: 'noopener noreferrer', text: `Open on ${host}` }),
        );
      });
      frameHost.append(button);
      return frameHost;
    }
    return el('div', { class: 'link-card' }, [
      el('div', { class: 'meta' }, [
        el('strong', { text: host }),
        el('small', { text: raw }),
      ]),
      el('a', { class: 'go', href: raw, target: '_blank', rel: 'noopener noreferrer', text: 'Open' }),
    ]);
  }

  const url = storagePublicUrl(SUPABASE_URL, att.storage_path);
  const name = String(att.original_filename || 'Attachment');
  const size = formatBytes(att.file_size_bytes);
  if (!url) {
    return el('div', { class: 'file-card' }, [el('div', { class: 'meta' }, [el('strong', { text: name }), el('small', { text: 'File unavailable' })])]);
  }
  if (kind === 'image') {
    return imageTile(url, name);
  }
  if (kind === 'video') {
    return el('video', {
      controls: 'controls',
      preload: 'metadata',
      playsinline: 'playsinline',
      src: url,
      'aria-label': name,
    });
  }
  const isPdf = String(att.mime_type || '').toLowerCase() === 'application/pdf';
  return el('div', { class: 'file-card' }, [
    el('div', { class: 'meta' }, [
      el('strong', { text: name }),
      el('small', { text: [isPdf ? 'PDF document' : String(att.mime_type || 'File'), size].filter(Boolean).join(' · ') }),
    ]),
    el('a', { class: 'go', href: url, target: '_blank', rel: 'noopener noreferrer', text: isPdf ? 'Open PDF' : 'Download' }),
  ]);
}

function attachmentsNode(post) {
  const list = Array.isArray(post.post_attachments) ? [...post.post_attachments] : [];
  if (!list.length && !post.image_path) return null;
  list.sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0));
  const box = el('div', { class: 'attachments' });
  const images = list.filter((a) => a.kind === 'image');
  const others = list.filter((a) => a.kind !== 'image');
  if (images.length) {
    const grid = el('div', { class: 'image-grid' });
    for (const image of images) grid.append(attachmentNode(image));
    box.append(grid);
  }
  for (const other of others) box.append(attachmentNode(other));
  // Legacy single-image rows stay visible until the backfill covers them.
  if (!list.length && post.image_path) {
    const url = storagePublicUrl(SUPABASE_URL, post.image_path);
    if (url) {
      const grid = el('div', { class: 'image-grid' });
      grid.append(imageTile(url, 'Attached photo'));
      box.append(grid);
    }
  }
  return box;
}

function authorHead(post) {
  const card = state.authors.get(post.user_id);
  const profileUrl = isUuid(post.user_id) ? profilePermalink(SITE_BASE, post.user_id) : null;
  const nameNode = profileUrl
    ? el('a', { class: 'name', href: profileUrl, text: authorLabel(card) })
    : el('span', { class: 'name', text: authorLabel(card) });
  const handle = card && card.display_name && card.username ? `@${card.username}` : null;
  return el('div', { class: 'post-head' }, [
    el('div', { class: 'avatar', 'aria-hidden': 'true', text: initialsFor(card) }),
    el('div', { class: 'who' }, [nameNode, handle ? el('span', { class: 'handle', text: handle }) : null]),
    el('time', { datetime: String(post.created_at || ''), text: relativeTime(post.created_at) }),
  ]);
}

function engagementNode(post) {
  const stats = state.stats.get(post.id) || {};
  const parts = [];
  if (stats.like_count) parts.push(`${stats.like_count} like${stats.like_count === 1 ? '' : 's'}`);
  if (stats.dislike_count) parts.push(`${stats.dislike_count} dislike${stats.dislike_count === 1 ? '' : 's'}`);
  const rating = ratingLabel(stats);
  if (rating) parts.push(rating);
  if (stats.comment_count) parts.push(`${stats.comment_count} comment${stats.comment_count === 1 ? '' : 's'}`);
  if (!parts.length) return null;
  return el('div', { class: 'engagement' }, parts.map((part) => el('span', { text: part })));
}

function postCard(post, { linkTitle = false } = {}) {
  const permalink = postPermalink(SITE_BASE, post.id);
  const body = el('p', { class: 'body', text: post.body || '' });
  const card = el('article', { class: 'post-card' }, [
    authorHead(post),
    body,
    attachmentsNode(post),
    engagementNode(post),
    el('div', { class: 'post-actions' }, [
      el('a', { href: permalink, text: 'Permalink' }),
      el('a', { href: appLink(`post/${post.id}`), text: 'Open in app' }),
      el('a', { href: profilePermalink(SITE_BASE, post.user_id), text: 'Author' }),
    ]),
  ]);
  if (linkTitle) {
    const heading = el('h2', { style: 'font-size:1rem;margin:0 0 .35rem' }, [
      el('a', { href: permalink, text: 'Open this post' }),
    ]);
    card.prepend(heading);
  }
  return card;
}

// ------------------------------------------------------------------- pages

async function renderFeed() {
  const list = document.getElementById('feed');
  if (!list) return;
  const posts = await rest('posts', {
    select: '*,post_attachments(*)',
    order: 'created_at.desc,id.desc',
    limit: 20,
  });
  await loadAuthors(posts.map((p) => p.user_id));
  await loadStats(posts.map((p) => p.id));
  clear(list);
  if (!posts.length) {
    list.append(el('div', { class: 'status', text: 'No posts yet. Share the first station tip from the RailMate BD app.' }));
    return;
  }
  for (const post of posts) list.append(postCard(post, { linkTitle: false }));
  const stamp = document.getElementById('refreshed');
  if (stamp) stamp.textContent = `Live · refreshed ${new Date().toLocaleTimeString()}`;
}

async function renderPost() {
  const id = new URLSearchParams(location.search).get('id') || '';
  const host = document.getElementById('post');
  const commentsHost = document.getElementById('comments');
  if (!host) return;
  if (!isUuid(id)) {
    status('That link does not contain a valid post id.', { error: true });
    return;
  }
  const post = await rest('posts', {
    select: '*,post_attachments(*)',
    filters: { id: `eq.${id}` },
    single: true,
  });
  if (!post) {
    status('This post is not available. It may have been deleted.', { error: true });
    return;
  }
  await loadAuthors([post.user_id]);
  await loadStats([post.id]);
  document.title = `${authorLabel(state.authors.get(post.user_id))} on RailMate BD`;
  clear(host);
  host.append(postCard(post));
  const canonical = document.getElementById('canonical');
  if (canonical) canonical.href = postPermalink(SITE_BASE, post.id);

  if (commentsHost) {
    const rows = await rest('post_comments', {
      select: 'id,user_id,body,created_at',
      filters: { post_id: `eq.${id}` },
      order: 'created_at.asc',
      limit: 100,
    });
    await loadAuthors(rows.map((r) => r.user_id));
    clear(commentsHost);
    commentsHost.append(el('h2', { text: `Comments (${rows.length})` }));
    if (!rows.length) {
      commentsHost.append(el('p', { class: 'empty', text: 'No comments yet. Add one from the RailMate BD app.' }));
    } else {
      const ul = el('ul');
      for (const row of rows) {
        const card = state.authors.get(row.user_id);
        ul.append(el('li', {}, [
          el('div', { class: 'meta', text: `${authorIdentity(card)} · ${formatDate(row.created_at)}` }),
          el('p', { text: row.body || '' }),
        ]));
      }
      commentsHost.append(ul);
    }
  }
}

async function renderProfile() {
  const id = new URLSearchParams(location.search).get('id') || '';
  const host = document.getElementById('profile');
  const postsHost = document.getElementById('posts');
  if (!host) return;
  if (!isUuid(id)) {
    status('That link does not contain a valid profile id.', { error: true });
    return;
  }
  const card = await rest('public_profile_cards', {
    select: 'id,username,display_name,joined_at,post_count',
    filters: { id: `eq.${id}` },
    single: true,
  });
  if (!card) {
    status('This profile is not available.', { error: true });
    return;
  }
  state.authors.set(card.id, card);
  document.title = `${authorLabel(card)} on RailMate BD`;
  clear(host);
  host.append(
    el('div', { class: 'profile-card' }, [
      el('div', { class: 'avatar', 'aria-hidden': 'true', text: initialsFor(card) }),
      el('div', {}, [
        el('h1', { text: authorLabel(card) }),
        card.username ? el('div', { class: 'sub', text: `@${card.username}` }) : null,
        el('div', {
          class: 'sub',
          text: `${card.joined_at ? `Joined ${formatDate(card.joined_at).split(',')[0]} · ` : ''}${card.post_count || 0} posts`,
        }),
      ]),
    ]),
  );
  if (!postsHost) return;
  const posts = await rest('posts', {
    select: '*,post_attachments(*)',
    filters: { user_id: `eq.${id}` },
    order: 'created_at.desc,id.desc',
    limit: 50,
  });
  await loadStats(posts.map((p) => p.id));
  clear(postsHost);
  if (!posts.length) {
    postsHost.append(el('div', { class: 'status', text: 'No public posts yet.' }));
    return;
  }
  for (const post of posts) postsHost.append(postCard(post));
}

// ------------------------------------------------------------------- boot

function startPolling(render) {
  const tick = async () => {
    if (document.hidden) return;
    try {
      await render();
      hideStatus();
    } catch (err) {
      status(`Could not load live data (${err.message}).`, { error: true, retry: () => tick() });
    }
  };
  state.timer = setInterval(tick, POLL_MS);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) tick();
  });
  return tick;
}

async function boot() {
  if (!requireConfig()) return;
  const page = document.body.dataset.page;
  const render = page === 'post' ? renderPost : page === 'profile' ? renderProfile : renderFeed;
  const tick = startPolling(render);
  await tick();
}

boot();
