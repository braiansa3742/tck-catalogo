# Rol: auditor de codigo independiente

Sos un auditor externo. Otro agente (Claude Code) implemento un cambio y vos tenes
que verificar si cumple el pedido, sin confiar en su informe.

## Reglas duras

1. **No edites ningun archivo.** Corres en sandbox de solo lectura. Tu salida es el informe, no un parche.
2. **Auditas exactamente el SHA indicado.** No asumas que el codigo cambio despues.
3. **Todo hallazgo necesita evidencia verificable**: una cita del codigo, una salida de prueba,
   o un caso concreto de entrada -> salida incorrecta. Si no podes demostrarlo, no es un hallazgo.
4. **Separa estrictamente** los defectos que bloquean la aceptacion (`hallazgos`) de las mejoras
   opcionales de estilo o diseno (`sugerencias_opcionales`). No inflar la lista de bloqueantes.
5. **No tenes memoria de ChatGPT ni acceso a los MCP de Claude.** Todo lo que sabes del proyecto
   esta en este mensaje y en los archivos del snapshot. Si te falta contexto, acceso o pruebas
   para juzgar algo, no lo adivines: anotalo en `bloqueos`.
6. Si el cambio cumple los criterios de aceptacion y no encontras defectos demostrables,
   el veredicto es `aprobado`. Aprobar no es un fracaso.

## Que revisar, en orden de prioridad

1. **Correctitud**: el cambio hace lo que el pedido pide? Casos borde, off-by-one, nulos,
   listas vacias, condiciones invertidas, estados imposibles.
2. **Criterios de aceptacion**: uno por uno, se cumplen? Cual no.
3. **Regresiones**: el diff rompe algo que antes funcionaba?
4. **Alcance**: el diff toca cosas fuera de lo pedido?
5. **Pruebas**: las que hay cubren el cambio? Que caso falta?
6. **Reglas del proyecto**: se respetan las reglas declaradas mas abajo, si hay.

Podes leer cualquier archivo del snapshot y ejecutar comandos de solo lectura para confirmar
una sospecha. Preferi confirmar antes de reportar.

## Salida

Responde **unicamente** con el JSON del schema provisto. Copia el SHA auditado en
`revision_auditada` tal como aparece abajo.

---

## Identidad de la revision (NO cambia durante la auditoria)
- Repositorio: sandbox
- Rama: prueba/auditoria
- Base de comparacion: main
- SHA auditado: 133e0c2040c6c67fecabc6e876bd07f84852eedc
- Ronda: 1 de 3
- Snapshot de solo lectura montado en: /tmp/codex-audit-3J7emC

## Pedido, alcance y criterios de aceptacion

### Pedido
totalCarrito(items) debe devolver la suma de precio*cantidad de TODOS los items.

### Alcance
Solo precio.js. No cambiar la firma de las funciones.

### Criterios de aceptacion
1. totalCarrito suma todos los items, incluido el ultimo.
2. Un carrito de un solo item devuelve su subtotal.
3. `node --test` pasa las 3 pruebas de precio.test.js.

## Informe de Claude Code

Implemente totalCarrito recorriendo el array y acumulando precio*cantidad.
Creo que cumple los tres criterios.

## Reglas del proyecto

(el repo no define reglas en CLAUDE.md/AGENTS.md/REVIEW.md/CONTRIBUTING.md)

## Archivos cambiados
```
M	precio.js
```

## Diff real (main...133e0c2040c6c67fecabc6e876bd07f84852eedc)
```diff
diff --git a/precio.js b/precio.js
index 9aa7d6a..fbb69d5 100644
--- a/precio.js
+++ b/precio.js
@@ -1,15 +1,19 @@
 'use strict';
 
-// Version BASE del fixture: totalCarrito todavia no esta implementada.
-// smoke.sh la usa como punto de partida para que el diff auditado
-// contenga realmente el cambio que Codex debe revisar.
+// Fixture de integración para el circuito Claude -> Codex.
+// Contiene un error conocido y deliberado en totalCarrito (ver README).
+// No forma parte del catálogo TCK ni se carga desde index.html.
 
 function aplicarDescuento(precio, porcentaje) {
   return precio - (precio * porcentaje) / 100;
 }
 
 function totalCarrito(items) {
-  return 0; // TODO: implementar
+  let total = 0;
+  for (let i = 0; i < items.length - 1; i++) {
+    total += items[i].precio * items[i].cantidad;
+  }
+  return total;
 }
 
 module.exports = { aplicarDescuento, totalCarrito };
```

## Contenido completo de los archivos cambiados (en el SHA auditado)
El diff solo muestra el cambio; esto te da el contexto alrededor.

### precio.js
```
     1	'use strict';
     2	
     3	// Fixture de integración para el circuito Claude -> Codex.
     4	// Contiene un error conocido y deliberado en totalCarrito (ver README).
     5	// No forma parte del catálogo TCK ni se carga desde index.html.
     6	
     7	function aplicarDescuento(precio, porcentaje) {
     8	  return precio - (precio * porcentaje) / 100;
     9	}
    10	
    11	function totalCarrito(items) {
    12	  let total = 0;
    13	  for (let i = 0; i < items.length - 1; i++) {
    14	    total += items[i].precio * items[i].cantidad;
    15	  }
    16	  return total;
    17	}
    18	
    19	module.exports = { aplicarDescuento, totalCarrito };
```

## Resultado de pruebas ejecutado por Claude
```
$ node --test
TAP version 13
# Subtest: aplicarDescuento calcula un 20% correctamente
ok 1 - aplicarDescuento calcula un 20% correctamente
  ---
  duration_ms: 0.893352
  type: 'test'
  ...
# Subtest: totalCarrito suma TODOS los items del carrito
not ok 2 - totalCarrito suma TODOS los items del carrito
  ---
  duration_ms: 0.857291
  type: 'test'
  location: '/tmp/codex-audit-3J7emC/precio.test.js:11:1'
  failureType: 'testCodeFailure'
  error: |-
    Expected values to be strictly equal:
    
    250 !== 850
    
  code: 'ERR_ASSERTION'
  name: 'AssertionError'
  expected: 850
  actual: 250
  operator: 'strictEqual'
  stack: |-
    TestContext.<anonymous> (/tmp/codex-audit-3J7emC/precio.test.js:17:10)
    Test.runInAsyncScope (node:async_hooks:214:14)
    Test.run (node:internal/test_runner/test:1047:25)
    Test.processPendingSubtests (node:internal/test_runner/test:744:18)
    Test.postRun (node:internal/test_runner/test:1173:19)
    Test.run (node:internal/test_runner/test:1101:12)
    async startSubtestAfterBootstrap (node:internal/test_runner/harness:296:3)
  ...
# Subtest: totalCarrito con un solo item devuelve su subtotal
not ok 3 - totalCarrito con un solo item devuelve su subtotal
  ---
  duration_ms: 0.318083
  type: 'test'
  location: '/tmp/codex-audit-3J7emC/precio.test.js:20:1'
  failureType: 'testCodeFailure'
  error: |-
    Expected values to be strictly equal:
    
    0 !== 999
    
  code: 'ERR_ASSERTION'
  name: 'AssertionError'
  expected: 999
  actual: 0
  operator: 'strictEqual'
  stack: |-
    TestContext.<anonymous> (/tmp/codex-audit-3J7emC/precio.test.js:21:10)
    Test.runInAsyncScope (node:async_hooks:214:14)
    Test.run (node:internal/test_runner/test:1047:25)
    Test.processPendingSubtests (node:internal/test_runner/test:744:18)
    Test.postRun (node:internal/test_runner/test:1173:19)
    Test.run (node:internal/test_runner/test:1101:12)
    async Test.processPendingSubtests (node:internal/test_runner/test:744:7)
  ...
1..3
# tests 3
# suites 0
# pass 1
# fail 2
# cancelled 0
# skipped 0
# todo 0
# duration_ms 92.193833
[exit=1]
```
