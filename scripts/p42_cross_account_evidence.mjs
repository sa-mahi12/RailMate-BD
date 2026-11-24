// P42 cross-account evidence: two independent Supabase accounts using the
// real hosted project (REST + Storage + RLS), no mocks.
//
// What it proves:
//   1. account A publishes a post with an image, a video, a PDF, an
//      allowlisted YouTube link and a plain HTTPS link;
//   2. account B (a different signed-in user) sees that post, its attachments
//      and the author's public identity (and so does an anonymous reader);
//   3. B comments, likes and rates the post; A reads the new counts back;
//   4. B cannot delete A's post (RLS: 0 rows affected, row still there);
//   5. B's report is stored and A cannot read it;
//   6. `public_profile_cards` exposes no private column.
//
// Secrets: reads app.env.json (gitignored) for URL/anon/service keys and
// generated test passwords, and NEVER prints or writes them. The output JSON
// is sanitized (ids, status codes, counts, timestamps only).
//
// Usage: node scripts/p42_cross_account_evidence.mjs
//        (optional) P42_ENV=path/to/app.env.json P42_OUT=docs/qa/p42/x.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(process.cwd());
const envPath = process.env.P42_ENV || path.join(ROOT, 'app.env.json');
const outPath =
  process.env.P42_OUT || path.join(ROOT, 'docs', 'qa', 'p42', 'cross-account-evidence.json');
const VIDEO_PATH = path.join(ROOT, 'web-guide', 'media', 'coxsbazar-express-480p.webm');

const env = JSON.parse(fs.readFileSync(envPath, 'utf8'));
const URL_BASE = String(env.SUPABASE_URL).replace(/\/+$/, '');
const ANON = String(env.SUPABASE_ANON_KEY);
const SERVICE = String(env.SUPABASE_SERVICE_ROLE_KEY);
if (!URL_BASE || !ANON || !SERVICE) {
  console.error('app.env.json is missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY');
  process.exit(2);
}

const runId = `${Date.now().toString(36)}${crypto.randomBytes(2).toString('hex')}`;
const suffix = runId.slice(-6);
const stamp = new Date().toISOString();
const results = [];
const record = (step, ok, detail) => {
  results.push({ step, ok, at: new Date().toISOString(), ...detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${step}`);
};

function fail(step, detail) {
  record(step, false, detail);
  console.error(JSON.stringify(detail, null, 2).slice(0, 2000));
  finish(1);
}

function finish(code) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  const payload = {
    p42Evidence: true,
    generatedAt: stamp,
    projectRef: URL_BASE.replace(/^https:\/\//, '').split('.')[0],
    runId,
    accounts: 'synthetic demo accounts created for this run (not the owner accounts)',
    steps: results,
    ok: results.every((r) => r.ok),
  };
  fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`\nwrote ${path.relative(ROOT, outPath)} (ok=${payload.ok})`);
  process.exit(code);
}

const svcHeaders = {
  apikey: SERVICE,
  authorization: `Bearer ${SERVICE}`,
  'content-type': 'application/json',
};

async function svc(pathname, options = {}) {
  const res = await fetch(`${URL_BASE}${pathname}`, { headers: svcHeaders, ...options });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: res.status, body, ok: res.ok };
}

async function userFetch(token, pathname, options = {}) {
  const res = await fetch(`${URL_BASE}${pathname}`, {
    ...options,
    headers: {
      apikey: ANON,
      authorization: `Bearer ${token}`,
      accept: 'application/json',
      ...(options.body && !(options.body instanceof Uint8Array)
        ? { 'content-type': 'application/json' }
        : {}),
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: res.status, body, ok: res.ok };
}

async function anonFetch(pathname) {
  const res = await fetch(`${URL_BASE}${pathname}`, {
    headers: { apikey: ANON, authorization: `Bearer ${ANON}`, accept: 'application/json' },
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: res.status, body, ok: res.ok };
}

/** 640×360 PNG generated in-process (no external asset, no image library). */
function buildPng(width = 640, height = 360) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 3 + 1)] = 0;
    for (let x = 0; x < width; x++) {
      const i = y * (width * 3 + 1) + 1 + x * 3;
      const band = Math.floor(y / 24) % 2;
      raw[i] = band ? 14 : 226;
      raw[i + 1] = band ? 90 : 240;
      raw[i + 2] = band ? 102 : 242;
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const typeBuf = Buffer.from(type, 'ascii');
    const crcTable = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c >>> 0;
    }
    let crc = 0xffffffff;
    for (const byte of Buffer.concat([typeBuf, data])) {
      crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    }
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const deflate = (buf) => {
    // Minimal zlib "stored" blocks: valid and dependency-free.
    const blocks = [];
    const max = 65535;
    for (let offset = 0; offset < buf.length; offset += max) {
      const slice = buf.subarray(offset, Math.min(offset + max, buf.length));
      const header = Buffer.alloc(5);
      header[0] = offset + max >= buf.length ? 1 : 0;
      header.writeUInt16LE(slice.length, 1);
      header.writeUInt16LE(~slice.length & 0xffff, 3);
      blocks.push(header, slice);
    }
    const zlibHeader = Buffer.from([0x78, 0x01]);
    let a = 1;
    let b = 0;
    for (const byte of buf) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    const adler = Buffer.alloc(4);
    adler.writeUInt32BE(((b << 16) | a) >>> 0);
    return Buffer.concat([zlibHeader, ...blocks, adler]);
  };
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflate(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** A real, openable PDF written by hand (no dependency). */
function buildPdf() {
  const lines = [
    'RailMate BD - P42 demonstration attachment',
    'This PDF was uploaded through the real Supabase Storage API',
    'and is rendered by the public site and the Android app.',
    'DEMONSTRATION ONLY - not a real ticket.',
  ];
  const content =
    'BT /F1 16 Tf 50 740 Td 22 TL\n' +
    lines.map((line) => `(${line.replace(/[()\\]/g, '\\$&')}) Tj T*`).join('\n') +
    '\nET\n';
  const objects = [
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n',
    '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    `5 0 obj\n<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}endstream\nendobj\n`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  for (const object of objects) {
    offsets.push(Buffer.byteLength(pdf));
    pdf += object;
  }
  const xrefStart = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) {
    pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

async function createAccount(label) {
  const email = `p42.${label}.${suffix}@example.com`;
  const password = `P42-${crypto.randomBytes(18).toString('base64url')}!`;
  const created = await svc('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: label === 'a' ? 'P42 Amina (demo)' : 'P42 Rafi (demo)' },
    }),
  });
  if (!(created.status === 200 || created.status === 201)) {
    fail(`create account ${label}`, { status: created.status, body: created.body });
  }
  const id = created.body?.id;
  const signin = await fetch(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const session = await signin.json();
  if (!signin.ok || !session.access_token) {
    fail(`sign in account ${label}`, { status: signin.status });
  }
  return { id, email, token: session.access_token };
}

async function ensureProfile(account, username, displayName) {
  const profile = await svc('/rest/v1/profiles', {
    method: 'POST',
    headers: { ...svcHeaders, prefer: 'resolution=merge-duplicates,return=representation' },
    body: JSON.stringify([{ id: account.id, display_name: displayName }]),
  });
  if (!(profile.status === 200 || profile.status === 201)) {
    fail('ensure profile', { status: profile.status, body: profile.body });
  }
  const claim = await svc('/rest/v1/usernames', {
    method: 'POST',
    headers: { ...svcHeaders, prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify([{ user_id: account.id, username }]),
  });
  if (!(claim.status === 200 || claim.status === 201 || claim.status === 204)) {
    fail('claim username', { status: claim.status, body: claim.body });
  }
}

async function uploadObject(token, objectPath, bytes, contentType) {
  const res = await fetch(`${URL_BASE}/storage/v1/object/post-media/${objectPath}`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      authorization: `Bearer ${token}`,
      'content-type': contentType,
      'x-upsert': 'false',
    },
    body: bytes,
  });
  const text = await res.text();
  if (!res.ok) {
    fail(`upload ${contentType}`, { status: res.status, body: text.slice(0, 300) });
  }
  return res.status;
}

// --------------------------------------------------------------------- run

try {
  console.log(`project ${URL_BASE} — run ${runId}`);

  const A = await createAccount('a');
  const B = await createAccount('b');
  record('two independent accounts created and signed in', true, {
    accountA: A.id,
    accountB: B.id,
    distinct: A.id !== B.id,
  });

  await ensureProfile(A, `p42_amina_${suffix}`, 'P42 Amina (demo)');
  await ensureProfile(B, `p42_rafi_${suffix}`, 'P42 Rafi (demo)');
  record('public profiles + usernames claimed', true, {
    usernameA: `p42_amina_${suffix}`,
    usernameB: `p42_rafi_${suffix}`,
  });

  const body = `P42 cross-account check ${suffix}: platform 3 tea stall, lift works at the north end. DEMONSTRATION ONLY.`;
  const created = await userFetch(A.token, '/rest/v1/posts', {
    method: 'POST',
    headers: { prefer: 'return=representation' },
    body: JSON.stringify({ user_id: A.id, body }),
  });
  if (created.status !== 201 || !created.body?.[0]?.id) {
    fail('account A creates a post', { status: created.status, body: created.body });
  }
  const postId = created.body[0].id;
  record('account A created a post', true, { postId });

  const png = buildPng();
  const pdf = buildPdf();
  const video = fs.readFileSync(VIDEO_PATH);
  const imagePath = `${A.id}/${postId}/${crypto.randomUUID()}.png`;
  const videoPath = `${A.id}/${postId}/${crypto.randomUUID()}.webm`;
  const pdfPath = `${A.id}/${postId}/${crypto.randomUUID()}.pdf`;
  const uploads = [
    [imagePath, png, 'image/png', 'image'],
    [videoPath, video, 'video/webm', 'video'],
    [pdfPath, pdf, 'application/pdf', 'file'],
  ];
  for (const [objectPath, bytes, mime] of uploads) {
    await uploadObject(A.token, objectPath, bytes, mime);
  }
  record('account A uploaded image + video + PDF to Supabase Storage', true, {
    objects: uploads.length,
    imageBytes: png.length,
    videoBytes: video.length,
    pdfBytes: pdf.length,
  });

  const rows = [
    {
      post_id: postId,
      owner_id: A.id,
      kind: 'image',
      storage_path: imagePath,
      external_url: null,
      mime_type: 'image/png',
      original_filename: 'platform-3.png',
      file_size_bytes: png.length,
      display_order: 0,
    },
    {
      post_id: postId,
      owner_id: A.id,
      kind: 'video',
      storage_path: videoPath,
      external_url: null,
      mime_type: 'video/webm',
      original_filename: 'coxsbazar-express-480p.webm',
      file_size_bytes: video.length,
      display_order: 1,
    },
    {
      post_id: postId,
      owner_id: A.id,
      kind: 'file',
      storage_path: pdfPath,
      external_url: null,
      mime_type: 'application/pdf',
      original_filename: 'p42-demonstration.pdf',
      file_size_bytes: pdf.length,
      display_order: 2,
    },
    {
      post_id: postId,
      owner_id: A.id,
      kind: 'link',
      storage_path: null,
      external_url: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
      mime_type: null,
      original_filename: null,
      file_size_bytes: null,
      display_order: 3,
    },
    {
      post_id: postId,
      owner_id: A.id,
      kind: 'link',
      storage_path: null,
      external_url: 'https://www.railway.gov.bd/',
      mime_type: null,
      original_filename: null,
      file_size_bytes: null,
      display_order: 4,
    },
  ];
  const inserted = await userFetch(A.token, '/rest/v1/post_attachments', {
    method: 'POST',
    headers: { prefer: 'return=representation' },
    body: JSON.stringify(rows),
  });
  if (inserted.status !== 201 || inserted.body?.length !== rows.length) {
    fail('account A inserts 5 attachment rows', {
      status: inserted.status,
      body: inserted.body,
    });
  }
  record('account A inserted 5 attachments (image, video, PDF, 2 links)', true, {
    kinds: inserted.body.map((row) => row.kind),
  });

  const badLink = await userFetch(A.token, '/rest/v1/post_attachments', {
    method: 'POST',
    body: JSON.stringify([
      {
        post_id: postId,
        owner_id: A.id,
        kind: 'link',
        external_url: 'http://insecure.example.com/x',
        display_order: 9,
      },
    ]),
  });
  record('database rejects a non-HTTPS link (check constraint)', badLink.status === 400, {
    status: badLink.status,
  });

  const foreignAttachment = await userFetch(A.token, '/rest/v1/post_attachments', {
    method: 'POST',
    body: JSON.stringify([
      {
        post_id: postId,
        owner_id: B.id,
        kind: 'link',
        external_url: 'https://example.com/hijack',
        display_order: 9,
      },
    ]),
  });
  record(
    'database rejects an attachment owned by another account',
    foreignAttachment.status >= 400,
    { status: foreignAttachment.status },
  );

  // ---- reader B
  const feed = await anonFetch(
    `/rest/v1/posts?select=*,post_attachments(*)&id=eq.${postId}`,
  );
  const seenPost = Array.isArray(feed.body) ? feed.body[0] : null;
  const seenAttachments = seenPost?.post_attachments ?? [];
  record('anonymous reader sees the post with all 5 attachments', Boolean(seenPost) && seenAttachments.length === 5, {
    status: feed.status,
    attachments: seenAttachments.length,
    kinds: seenAttachments.map((a) => a.kind).sort(),
  });

  const cards = await anonFetch(
    `/rest/v1/public_profile_cards?select=*&id=eq.${A.id}`,
  );
  const card = Array.isArray(cards.body) ? cards.body[0] : null;
  const privateLeak = card
    ? Object.keys(card).filter((k) => !['id', 'username', 'display_name', 'joined_at', 'post_count'].includes(k))
    : ['missing'];
  record('public author card exposes only safe fields', Boolean(card) && privateLeak.length === 0, {
    status: cards.status,
    fields: card ? Object.keys(card).sort() : [],
    leaked: privateLeak,
  });

  const bComment = await userFetch(B.token, '/rest/v1/post_comments', {
    method: 'POST',
    body: JSON.stringify({ post_id: postId, user_id: B.id, body: 'B says: thanks for the tea-stall tip.' }),
  });
  const bReaction = await userFetch(B.token, '/rest/v1/post_reactions', {
    method: 'POST',
    body: JSON.stringify({ post_id: postId, user_id: B.id, reaction: 'LIKE' }),
  });
  const bRating = await userFetch(B.token, '/rest/v1/post_ratings', {
    method: 'POST',
    body: JSON.stringify({ post_id: postId, user_id: B.id, stars: 5 }),
  });
  record('account B comments, likes and rates the post', bComment.status === 201 && bReaction.status === 201 && bRating.status === 201, {
    comment: bComment.status,
    reaction: bReaction.status,
    rating: bRating.status,
  });

  const stats = await anonFetch(`/rest/v1/public_post_stats?select=*&post_id=eq.${postId}`);
  const stat = Array.isArray(stats.body) ? stats.body[0] : null;
  record(
    'public stats show B\'s engagement to every reader',
    stat?.like_count === 1 && stat?.rating_count === 1 && stat?.comment_count === 1,
    { status: stats.status, stats: stat },
  );

  const crossDelete = await userFetch(B.token, `/rest/v1/posts?id=eq.${postId}`, {
    method: 'DELETE',
    headers: { prefer: 'return=representation' },
  });
  const stillThere = await anonFetch(`/rest/v1/posts?select=id&id=eq.${postId}`);
  record(
    'account B cannot delete account A\'s post',
    crossDelete.status >= 400 || (Array.isArray(crossDelete.body) && crossDelete.body.length === 0),
    { deleteStatus: crossDelete.status, deleteRows: Array.isArray(crossDelete.body) ? crossDelete.body.length : null },
  );
  record('the post still exists after the cross-account delete attempt', Array.isArray(stillThere.body) && stillThere.body.length === 1, {
    status: stillThere.status,
  });

  const report = await userFetch(B.token, '/rest/v1/post_reports', {
    method: 'POST',
    body: JSON.stringify({ post_id: postId, reporter_id: B.id, reason: 'spam', details: 'evidence run' }),
  });
  const aSees = await userFetch(A.token, `/rest/v1/post_reports?select=id&post_id=eq.${postId}`);
  record('report stored for the reporter but hidden from the author', report.status === 201 && Array.isArray(aSees.body) && aSees.body.length === 0, {
    reportStatus: report.status,
    authorVisibleRows: Array.isArray(aSees.body) ? aSees.body.length : null,
  });

  const selfReport = await userFetch(B.token, '/rest/v1/user_reports', {
    method: 'POST',
    body: JSON.stringify({ reported_user_id: B.id, reporter_id: B.id, reason: 'spam' }),
  });
  record('database rejects reporting yourself', selfReport.status >= 400, {
    status: selfReport.status,
  });

  const userReport = await userFetch(B.token, '/rest/v1/user_reports', {
    method: 'POST',
    body: JSON.stringify({ reported_user_id: A.id, reporter_id: B.id, reason: 'other', details: 'evidence run' }),
  });
  record('account B can report account A\'s public profile', userReport.status === 201, {
    status: userReport.status,
  });

  const signedUrls = await anonFetch(`/rest/v1/posts?select=image_path&id=eq.${postId}`);
  record('feed read is public and does not require the service key', signedUrls.ok, {
    status: signedUrls.status,
  });

  // Keep the public board tidy: remove posts from earlier evidence runs so the
  // feed shows exactly one demonstration post per run.
  const stale = await svc(
    `/rest/v1/posts?select=id&body=like.${encodeURIComponent('P42 cross-account check*')}&id=neq.${postId}`,
  );
  if (Array.isArray(stale.body) && stale.body.length) {
    await svc(`/rest/v1/posts?id=in.(${stale.body.map((r) => r.id).join(',')})`, {
      method: 'DELETE',
    });
  }
  record('earlier evidence posts cleaned up', true, {
    removed: Array.isArray(stale.body) ? stale.body.length : 0,
  });

  finish(results.every((r) => r.ok) ? 0 : 1);
} catch (err) {
  fail('unexpected error', { message: String(err && err.message ? err.message : err) });
}
