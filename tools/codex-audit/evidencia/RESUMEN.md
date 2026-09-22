# Evidencia: preparacion del circuito Claude Code -> Codex

Fecha: 2026-09-22. Todo lo de abajo se ejecuto de verdad; nada esta simulado ni supuesto.

## Entorno donde corrio esta sesion

**No fue tu PC.** Esta sesion corrio en un contenedor efimero de Claude Code en la nube:

- usuario `root` en host `vm`, Ubuntu 24.04.4 LTS, kernel 6.18.44-fc-v37
- carpeta de trabajo `/home/user/tck-catalogo`, repo git de `braiansa3742/tck-catalogo`
- no hay tools de `remote-devices`, asi que la sesion **no esta enlazada a tu maquina**

Consecuencia: nada de lo instalado aca queda en tu PC, y el contenedor se recicla.

## Estado de git al empezar (sin alterar nada)

Rama `claude/epic-pasteur-ihpzgu`, arbol limpio, HEAD `131b48a`. No se toco trabajo previo.

## Lo que SI se pudo verificar

| # | Verificacion | Resultado | Archivo |
|---|---|---|---|
| 1 | Codex CLI instalable por npm | `codex-cli 0.155.1` | `01-codex-version.txt` |
| 2 | Flags reales de `codex exec` | verificados con `--help` de la version instalada | (en README.md) |
| 3 | El fixture tiene un error real y las pruebas lo detectan | 2 de 3 pruebas fallan | `02-fixture-pruebas-fallan.txt` |
| 4 | El cableado Claude -> Codex funciona | Codex arranco, tomo el prompt por stdin, aplico `sandbox: read-only` y `approval: never`, abrio sesion | `03-codex-exec-red-bloqueada.log` |
| 5 | El arnes `audit.sh` funciona de punta a punta | ronda 1 = `cambios_requeridos` con 1 hallazgo; ronda 2 = `aprobado`; pruebas 3/3 | `05`, `06`, `07` |
| 6 | Parada correcta por falta de acceso | exit 10 con el binario real sin login | `08-parada-sin-login.txt` |
| 7 | Parada correcta por arbol sucio | exit 13, detecto archivos sin commitear | (en la transcripcion) |
| 8 | El snapshot auditado es inmutable | md5 del archivo en el worktree identico antes y despues de modificar el arbol principal | (en la transcripcion) |

Sobre el punto 5: se ejecuto con un `codex` de reemplazo (stub) en el PATH, porque no hay
red. Eso valida **el arnes** — armado del bundle, snapshot fijo, parseo del JSON, codigos de
salida — y **no** valida el juicio de Codex. El stub verifica ademas que el bundle contenga
las cinco piezas del circuito (identidad de la revision, pedido, informe de Claude, diff real,
resultado de pruebas) y aborta si falta alguna.

## Lo que NO se pudo verificar, y por que

**Una auditoria real de Codex sobre codigo.** Falta por dos razones independientes:

1. **Sin salida de red.** La politica de egreso del entorno deniega con 403 en el CONNECT
   hacia `api.openai.com`, `auth.openai.com`, `chatgpt.com` y `ab.chatgpt.com`.
   Ver `04-proxy-deniega-openai.json` y `03-codex-exec-red-bloqueada.log`.
   No se intento sortear el bloqueo.

2. **Sin login.** `codex login status` -> "Not logged in". Autenticar requiere tu cuenta de
   ChatGPT en un navegador. No se uso ninguna API key: no hay `OPENAI_API_KEY` en el entorno,
   y `audit.sh` la desactiva en cada invocacion igual.

Autenticar aca tampoco habria servido: el contenedor es efimero y no es tu PC, asi que
habria dejado un token de tu cuenta en una maquina descartable para nada.

**Conclusion honesta:** el circuito esta construido y su mecanica esta probada hasta el
limite de la red. La unica prueba que falta es el viaje de ida y vuelta a OpenAI, y se
completa corriendo `./smoke.sh` en tu PC despues de `codex login`.
