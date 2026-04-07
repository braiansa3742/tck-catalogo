// TCK Service Worker — v1
const CACHE = 'tck-v1';
const ASSETS = [
  '/',
  '/index.html',
  '/pedidos.html',
  '/manifest.json',
  '/manifest_catalogo.json',
  '/img/logo.png'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE).then(function(cache) {
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k){ return k !== CACHE; }).map(function(k){ return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(e) {
  // Solo cachear GET del mismo origen
  if (e.request.method !== 'GET') return;
  if (!e.request.url.startsWith(self.location.origin)) return;

  e.respondWith(
    fetch(e.request)
      .then(function(res) {
        // Guardar en caché copia fresca
        const clone = res.clone();
        caches.open(CACHE).then(function(cache){ cache.put(e.request, clone); });
        return res;
      })
      .catch(function() {
        // Si no hay red, usar caché
        return caches.match(e.request);
      })
  );
});
