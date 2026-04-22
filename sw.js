// ═══════════════════════════════════════════════════════════════════
// TCK Catálogo — Service Worker mínimo v1.0 (21/04/2026)
// ───────────────────────────────────────────────────────────────────
// Objetivo: habilitar instalabilidad PWA. Este SW NO cachea recursos
// todavía (para evitar problemas de estaleness mientras iteramos el
// catálogo). Solo existe para que el browser considere la app
// instalable y pase los checks de Lighthouse/Chrome.
//
// En una versión futura se puede agregar caché estratégica:
// - cache-first para /img/* (imágenes de productos)
// - network-first para /index.html (siempre la versión más nueva)
// - stale-while-revalidate para manifest y fuentes
// ═══════════════════════════════════════════════════════════════════

const SW_VERSION = 'tck-catalogo-v1.0';

// Instalación: activar de inmediato (sin esperar pestañas viejas)
self.addEventListener('install', function(event) {
  self.skipWaiting();
});

// Activación: tomar control de las pestañas abiertas
self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

// Fetch: pass-through (no cachea, solo deja pasar todo al network)
// Esto es intencional por ahora - queremos siempre la versión más nueva.
self.addEventListener('fetch', function(event) {
  // No interceptar - comportamiento default del browser
});
