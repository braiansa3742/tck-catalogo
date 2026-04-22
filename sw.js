// ═══════════════════════════════════════════════════════════════════
// TCK Catálogo — Service Worker v2.0 (21/04/2026)
// ───────────────────────────────────────────────────────────────────
// OBJETIVO: invalidar la caché del SW v3 anterior (que servía versiones
// viejas del index.html) y forzar a todos los clientes a traer la
// versión nueva de forma inmediata.
//
// ESTRATEGIA:
// - install:   skipWaiting() → no espera a que se cierren las pestañas viejas
// - activate:  borra TODAS las cachés anteriores + clients.claim() +
//              forzar reload de las pestañas que estaban con el SW viejo
// - fetch:     pass-through (no cachea) para que cada pedido siempre
//              traiga la versión más actual desde el network
//
// Cuando el catálogo esté estable, podemos volver a habilitar cache
// estratégica (ej. cache-first para /img/* pero network-first para /index.html).
// ═══════════════════════════════════════════════════════════════════

const SW_VERSION = 'tck-catalogo-v2.0';

self.addEventListener('install', function(event) {
  // No esperar que se cierren las pestañas viejas
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    Promise.all([
      // 1) Borrar TODAS las cachés anteriores (incluye 'tck-v3' del SW viejo)
      caches.keys().then(function(keys) {
        return Promise.all(keys.map(function(k) {
          return caches.delete(k);
        }));
      }),
      // 2) Tomar control de todas las pestañas abiertas YA
      self.clients.claim()
    ]).then(function() {
      // 3) Forzar reload de las pestañas que estaban usando el SW viejo.
      //    Esto garantiza que todos los clientes existentes reciban
      //    la versión más nueva del index.html en su próximo render.
      return self.clients.matchAll({ type: 'window' }).then(function(windowClients) {
        windowClients.forEach(function(client) {
          // navigate al mismo URL fuerza un reload con el SW nuevo activo
          if (client.url && 'navigate' in client) {
            client.navigate(client.url).catch(function() {});
          }
        });
      });
    })
  );
});

// Pass-through: no cachea nada. Cada request pasa directo al network.
// El browser sigue cacheando según los headers Cache-Control de GitHub Pages,
// que son razonables (unos minutos). Esto nos da la balance correcta:
// ni stale forever (SW viejo) ni network siempre (cero performance).
self.addEventListener('fetch', function(event) {
  // No interceptar - comportamiento default del browser
});
