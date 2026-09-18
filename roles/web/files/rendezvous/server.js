'use strict';
// Signalling rendezvous for Hulls & Hellfire.
//
// Holds a WebRTC offer under a short spoken code until the other phone claims
// it, then carries the answer back. That is the whole job: it never sees game
// traffic, and once both halves are exchanged the session is dropped.
//
// State is in memory on purpose — a session lives for minutes and is worthless
// after, so a restart losing them costs a player one retry, which is not worth
// a database.

const http = require('http');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8787);
const SESSION_TTL_MS = Number(process.env.SESSION_TTL_MS || 10 * 60 * 1000);
const MAX_BODY_BYTES = Number(process.env.MAX_BODY_BYTES || 64 * 1024);
const MAX_SESSIONS = Number(process.env.MAX_SESSIONS || 5000);

// No O/0 or I/1: the code gets read aloud across a table, and those are the
// pairs people mishear and mistype.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LEN = 6;

/** code -> { offer, answer, createdAt } */
const sessions = new Map();

function newCode() {
  for (let attempt = 0; attempt < 12; attempt++) {
    const bytes = crypto.randomBytes(CODE_LEN);
    let code = '';
    for (let i = 0; i < CODE_LEN; i++) code += ALPHABET[bytes[i] % ALPHABET.length];
    if (!sessions.has(code)) return code;
  }
  return null;
}

function sweep() {
  const cutoff = Date.now() - SESSION_TTL_MS;
  for (const [code, s] of sessions) if (s.createdAt < cutoff) sessions.delete(code);
}
setInterval(sweep, 30_000).unref();

// Crude per-IP limiter. A host publishing an offer is a rare action; anything
// hammering this endpoint is enumerating codes, not playing.
const hits = new Map();
setInterval(() => hits.clear(), 60_000).unref();
function rateLimited(ip, max = 60) {
  const n = (hits.get(ip) || 0) + 1;
  hits.set(ip, n);
  return n > max;
}

function send(res, status, body) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('body too large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {});
      } catch {
        reject(Object.assign(new Error('invalid json'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

const CODE_RE = new RegExp(`^[${ALPHABET}]{${CODE_LEN}}$`);

const server = http.createServer(async (req, res) => {
  const ip = req.socket.remoteAddress || 'unknown';
  if (rateLimited(ip)) return send(res, 429, { error: 'slow down' });

  const url = new URL(req.url, 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);

  try {
    if (req.method === 'GET' && parts[0] === 'health')
      return send(res, 200, { ok: true, sessions: sessions.size });

    // Host: publish an offer, receive a code.
    if (req.method === 'POST' && parts.length === 1 && parts[0] === 'session') {
      if (sessions.size >= MAX_SESSIONS) return send(res, 503, { error: 'at capacity' });
      const { offer } = await readBody(req);
      if (typeof offer !== 'string' || !offer) return send(res, 400, { error: 'offer required' });
      const code = newCode();
      if (!code) return send(res, 503, { error: 'at capacity' });
      sessions.set(code, { offer, answer: null, createdAt: Date.now() });
      return send(res, 201, { code, expiresInMs: SESSION_TTL_MS });
    }

    if (parts[0] !== 'session' || !parts[1] || !CODE_RE.test(parts[1])) {
      return send(res, 404, { error: 'not found' });
    }
    const code = parts[1];
    const session = sessions.get(code);
    if (!session) return send(res, 404, { error: 'no such game' });

    // Joiner: claim the offer.
    if (req.method === 'GET' && parts.length === 2) {
      return send(res, 200, { offer: session.offer });
    }

    // Joiner: hand back the answer.
    if (req.method === 'POST' && parts[2] === 'answer') {
      const { answer } = await readBody(req);
      if (typeof answer !== 'string' || !answer)
        return send(res, 400, { error: 'answer required' });
      session.answer = answer;
      return send(res, 204);
    }

    // Host: poll for it. 204 means "not yet", which is the normal case.
    if (req.method === 'GET' && parts[2] === 'answer') {
      if (!session.answer) return send(res, 204);
      // Both halves are across; nothing more to hold.
      sessions.delete(code);
      return send(res, 200, { answer: session.answer });
    }

    return send(res, 405, { error: 'method not allowed' });
  } catch (err) {
    return send(res, err.status || 500, { error: err.message || 'error' });
  }
});

server.listen(PORT, () => console.log(`rendezvous listening on :${PORT}`));
