// Animax reference backend — zero dependencies (Node 18+).
// Run:  node server.js   →  http://0.0.0.0:8000
//
// Point the Animax app at it:  Profile → API Backend → Base URL
//   http://<your-computer-lan-ip>:8000   (phone and computer on same Wi-Fi)
// Then tap "Save & Test Connection".
//
// This server implements exactly the JSON contract the app expects, so you
// can either use it as-is or mirror its shapes in your real backend.
const http = require('http');

const PORT = process.env.PORT || 8000;
const TOKEN = 'demo-jwt-token-12345';

// ---------------------------------------------------------------- catalog --
const animes = [
  {
    id: 'titan', title: 'Attack on Titan Final Season Part 2', slug: 'attack-on-titan-s4',
    poster: '/posters/titan.jpg', score: 9.7, year: '2022',
    genres: ['Action', 'Dark Fantasy', 'Post-Apocalyptic'],
    synopsis: 'The war for the fate of humanity reaches its climax as the walls fall and the island of Paradis faces the whole world. Old friends stand on opposite sides of the battlefield, and every choice demands a sacrifice.',
    episodeCount: 28, ageRating: '16+', type: 'TV', status: 'Finished', studio: 'MAPPA', duration: 24,
  },
  {
    id: 'slayer', title: 'Demon Slayer: Kimetsu no Yaiba', slug: 'demon-slayer',
    poster: '/posters/slayer.jpg', score: 9.8, year: '2022',
    genres: ['Action', 'Shounen', 'Martial Arts'],
    synopsis: 'After his family is slaughtered and his sister is turned into a demon, a kind-hearted young swordsman joins the Demon Slayer Corps to hunt the creatures of the night.',
    episodeCount: 26, ageRating: '13+', type: 'TV', status: 'Airing', studio: 'ufotable', duration: 24,
  },
  {
    id: 'spyfamily', title: 'Spy x Family', slug: 'spy-x-family',
    poster: '/posters/spyfamily.jpg', score: 9.6, year: '2023',
    genres: ['Action', 'Comedy', 'Slice of Life'],
    synopsis: 'A master spy must build a fake family to complete his hardest mission yet — except his daughter reads minds and his wife is an assassin.',
    episodeCount: 25, ageRating: '13+', type: 'TV', status: 'Airing', studio: 'Wit / CloverWorks', duration: 24,
  },
  {
    id: 'jjk', title: 'Jujutsu Kaisen Season 2', slug: 'jujutsu-kaisen-s2',
    poster: '/posters/jjk.jpg', score: 9.5, year: '2023',
    genres: ['Action', 'Supernatural', 'Dark Fantasy'],
    synopsis: 'Sorcerers battle cursed spirits born from human negativity as the Shibuya incident unfolds.',
    episodeCount: 23, ageRating: '16+', type: 'TV', status: 'Finished', studio: 'MAPPA', duration: 24,
  },
  {
    id: 'kaguya', title: 'Kaguya-sama: Love is War', slug: 'kaguya-sama',
    poster: '/posters/kaguya.jpg', score: 9.1, year: '2022',
    genres: ['Comedy', 'Romance', 'School'],
    synopsis: 'Two brilliant student council officers are hopelessly in love — and too proud to confess first.',
    episodeCount: 13, ageRating: '13+', type: 'TV', status: 'Finished', studio: 'A-1 Pictures', duration: 24,
  },
  {
    id: 'bocchi', title: 'Bocchi the Rock!', slug: 'bocchi-the-rock',
    poster: '/posters/bocchi.jpg', score: 8.8, year: '2022',
    genres: ['Comedy', 'Music', 'Slice of Life'],
    synopsis: 'A gifted but painfully shy guitarist joins a band hoping to shine on stage.',
    episodeCount: 12, ageRating: '13+', type: 'TV', status: 'Finished', studio: 'CloverWorks', duration: 23,
  },
  {
    id: 'onepiece', title: 'One Piece', slug: 'one-piece',
    poster: '/posters/onepiece.jpg', score: 9.0, year: '1999',
    genres: ['Adventure', 'Fantasy', 'Shounen'],
    synopsis: 'Monkey D. Luffy and his crew search the Grand Line for the legendary treasure known as the One Piece.',
    episodeCount: 1080, ageRating: '14+', type: 'TV', status: 'Airing', studio: 'Toei', duration: 24,
  },
  {
    id: 'filmred', title: 'One Piece Film: Red', slug: 'one-piece-film-red',
    poster: '/posters/filmred.jpg', score: 9.7, year: '2022',
    genres: ['Action', 'Adventure', 'Fantasy'],
    synopsis: 'The Straw Hats attend the world\u2019s most anticipated music festival, where singer Uta hides a plan that could change the age of pirates forever.',
    episodeCount: 1, ageRating: '14+', type: 'Movie', status: 'Finished', studio: 'Toei', duration: 116,
  },
];

// --------------------------------------------------------------- calendar --
// Keyed by day-of-month; each entry needs {time, episode} + anime ref.
const calendar = {
  18: [
    { time: '00:00', episode: 1079, animeId: 'onepiece' },
    { time: '20:30', episode: 13, animeId: 'kaguya' },
  ],
  19: [
    { time: '12:00', episode: 5, animeId: 'spyfamily' },
    { time: '22:00', episode: 12, animeId: 'bocchi' },
  ],
  20: [
    { time: '00:00', episode: 1080, animeId: 'onepiece' },
    { time: '12:00', episode: 12, animeId: 'jjk' },
  ],
  21: [
    { time: '12:00', episode: 24, animeId: 'slayer' },
    { time: '20:30', episode: 13, animeId: 'jjk' },
  ],
  22: [
    { time: '22:00', episode: 11, animeId: 'bocchi' },
    { time: '20:30', episode: 1, animeId: 'filmred' },
  ],
};

// ------------------------------------------------------------------ state --
const users = { 'andrew@animax.tv': { password: 'animax123', name: 'Andrew Stevenson' } };
const favoritesByUser = { 'andrew@animax.tv': ['titan', 'jjk'] };

// ----------------------------------------------------------------- helpers --
const posters = {
  '/posters/titan.jpg': 'assets/posters/titan.jpg',
  // The app falls back to a gradient tile when a poster 404s, so images are
  // optional. Replace with real URLs (e.g. your CDN) or serve files here.
};

function json(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Api-Key',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => { try { resolve(JSON.parse(raw || '{}')); } catch { resolve({}); } });
  });
}

// -------------------------------------------------------------- routes -----
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const auth = (req.headers.authorization || '').replace('Bearer ', '');
  const user = Object.keys(users).find((e) => favoritesByUser[e] && auth.startsWith('demo-jwt')) || 'andrew@animax.tv';

  if (req.method === 'OPTIONS') return json(res, 204, {});

  // Catalog (also serves as search: /animes?search=…)
  if (req.method === 'GET' && ['/animes', '/anime', '/catalog', '/titles'].includes(p)) {
    const q = (url.searchParams.get('search') || url.searchParams.get('q') || '').toLowerCase();
    const list = q ? animes.filter((a) => a.title.toLowerCase().includes(q)) : animes;
    return json(res, 200, { data: list });
  }

  // Single anime
  const detail = req.method === 'GET' && p.match(/^\/(animes|anime|catalog|titles)\/([^/]+)$/);
  if (detail) {
    const a = animes.find((x) => x.id === detail[2]);
    return a ? json(res, 200, { data: a }) : json(res, 404, { message: 'Not found' });
  }

  // Calendar
  if (req.method === 'GET' && ['/calendar', '/schedule'].includes(p)) return json(res, 200, calendar);

  // Notifications
  if (req.method === 'GET' && ['/notifications', '/notices'].includes(p)) {
    return json(res, 200, { data: [
      { animeId: 'onepiece', episode: 1080, createdAt: new Date(Date.now() - 2 * 3600e3).toISOString() },
      { animeId: 'jjk', episode: 12, createdAt: new Date(Date.now() - 26 * 3600e3).toISOString() },
      { animeId: 'filmred', episode: 1, createdAt: new Date(Date.now() - 3 * 86400e3).toISOString() },
    ] });
  }

  // My List / favorites
  if (p === '/favorites' || p === '/mylist') {
    if (req.method === 'GET') return json(res, 200, { data: favoritesByUser[user] });
    if (req.method === 'POST') {
      const body = await readBody(req);
      if (body.animeId && !favoritesByUser[user].includes(body.animeId)) favoritesByUser[user].push(body.animeId);
      return json(res, 200, { data: favoritesByUser[user] });
    }
  }
  const favDel = req.method === 'DELETE' && p.match(/^\/(favorites|mylist)\/([^/]+)$/);
  if (favDel) {
    favoritesByUser[user] = favoritesByUser[user].filter((id) => id !== favDel[2]);
    return json(res, 200, { ok: true });
  }

  // Auth
  if (req.method === 'POST' && ['/auth/login', '/login'].includes(p)) {
    const { email, password } = await readBody(req);
    const u = users[(email || '').toLowerCase()];
    if (!u || u.password !== password) return json(res, 401, { message: 'Wrong email or password' });
    return json(res, 200, { token: TOKEN, user: { name: u.name, email: email.toLowerCase() } });
  }
  if (req.method === 'POST' && ['/auth/register', '/register'].includes(p)) {
    const { email, password, name } = await readBody(req);
    if (!email || !password) return json(res, 400, { message: 'Email and password required' });
    users[email.toLowerCase()] = { password, name: name || email.split('@')[0] };
    favoritesByUser[email.toLowerCase()] = [];
    return json(res, 200, { token: TOKEN, user: { name: name || email.split('@')[0], email } });
  }

  return json(res, 404, { message: `No route for ${req.method} ${p}` });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Animax reference backend listening on http://0.0.0.0:${PORT}`);
  console.log(`Test login:  andrew@animax.tv / animax123`);
  console.log(`In the app:  Profile → API Backend → Base URL  http://<this-machine-LAN-ip>:${PORT}`);
});
