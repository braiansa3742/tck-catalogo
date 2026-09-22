# Circuito: Claude Code implementa, Codex audita

Claude Code hace el cambio; Codex (OpenAI) lo audita de forma no interactiva y devuelve
hallazgos estructurados. Nadie copia respuestas a mano.

Ambos lados usan **suscripcion**, no facturacion por API: Claude Max y ChatGPT.

---

## 1. Estado de la instalacion

Codex CLI **no quedo instalado en tu PC** desde esta sesion, porque esta sesion no corrio
en tu PC (ver `evidencia/RESUMEN.md`). Los pasos 2 y 3 los tenes que correr vos una sola vez.

## 2. Instalar Codex CLI (una vez, en tu PC)

Requiere Node.js 20 o superior.

```bash
npm install -g @openai/codex
codex --version
```

Alternativas oficiales: `brew install codex` en macOS, o el binario desde
[github.com/openai/codex/releases](https://github.com/openai/codex/releases).

En **Windows**, el sandbox de Codex no es nativo: usalo desde WSL2 para que
`-s read-only` (la garantia de que el auditor no edita) tenga efecto real.

En **Linux** el sandbox usa bubblewrap. Si `codex doctor` lo reporta faltante,
instalalo con el gestor de paquetes (`apt install bubblewrap`); si no, Codex usa
el bubblewrap que trae empaquetado.

## 3. Login con ChatGPT — **este paso lo tenes que hacer vos**

```bash
codex login
```

Abre el navegador y te pide iniciar sesion con tu cuenta de ChatGPT. Elegi
**"Sign in with ChatGPT"**, no la opcion de API key.

Si la terminal no puede abrir un navegador (servidor remoto, SSH):

```bash
codex login --device-auth
```

Verificar:

```bash
codex login status     # debe mencionar ChatGPT, no "API key"
codex doctor --summary
```

> Si `codex login status` dice que usa una API key, corre `codex logout` y repeti
> `codex login`. `audit.sh` se niega a correr con API key (exit 10) y desactiva
> `OPENAI_API_KEY` en cada invocacion, para no gastar credito facturado por error.

## 4. Probar que el intercambio funciona de verdad

```bash
cd tools/codex-audit
./smoke.sh
```

Crea un repo temporal **fuera de TCK** con un error conocido (un off-by-one en
`totalCarrito`), corre dos rondas reales de auditoria, corrige el error entre
medio y verifica con `node --test`. Imprime `PASA` solo si Codex detecto el error
en la ronda 1 y aprobo el codigo corregido en la ronda 2. Guarda todo en un
directorio de evidencia que te dice al terminar.

Esta es la prueba que valida el circuito. Corrila antes de usarlo con TCK.

---

## 5. Usar el circuito con TCK

### Paso a paso

```bash
# 1. Rama aislada
git checkout -b mejora/lo-que-sea

# 2. Escribi el pedido: que, hasta donde, y cuando esta aceptado
cat > /tmp/pedido.md <<'FIN'
### Pedido
<que hay que lograr>

### Alcance
<que archivos/areas se pueden tocar; que NO se toca>

### Criterios de aceptacion
1. <verificable>
2. <verificable>
FIN

# 3. Claude implementa y commitea (el arbol tiene que quedar limpio)

# 4. Auditoria
export AUDIT_TEST_CMD="node --test"        # o el comando de pruebas que corresponda
./tools/codex-audit/audit.sh \
    --pedido /tmp/pedido.md \
    --informe /tmp/informe-claude.md \
    --base main \
    --ronda 1
```

### Que recibe el auditor

`audit.sh` arma un bundle con: el pedido y los criterios de aceptacion, el informe
de Claude, las reglas del proyecto (`CLAUDE.md`, `AGENTS.md`, `REVIEW.md`,
`CONTRIBUTING.md` si existen), la lista de archivos cambiados, el diff real
`base...SHA`, el contenido completo de los archivos tocados, y la salida de las
pruebas que corrio Claude.

### Que devuelve

`.codex-audit/ronda-N-<sha>/findings.json`, con el schema de `findings.schema.json`:
cada hallazgo trae **archivo, ubicacion, impacto y evidencia**, y las mejoras
opcionales van en un array aparte (`sugerencias_opcionales`) que nunca bloquea.
Ademas quedan `bundle.md`, `cambios.diff`, `pruebas.txt` y `codex.log`.

### Garantias del diseno

| Garantia | Como |
|---|---|
| El auditor no edita el codigo | `codex exec -s read-only` |
| La version auditada no cambia mientras se audita | `git worktree --detach` en un SHA fijo; Claude puede seguir en el arbol principal |
| La version revisada es identificable | el SHA va en el bundle y en `findings.json.revision_auditada` |
| No se publica ni se fusiona nada | el script nunca hace `push`, `merge` ni toca bases de datos |
| No se gasta credito de API | `env -u OPENAI_API_KEY`; rechaza login por API key |
| No cambia tu configuracion global | todo por flags; nunca escribe `~/.codex/config.toml` |

### Rondas y cuando parar

Una implementacion inicial y **hasta 3 rondas** de correccion. Al llegar a la ronda 3
con hallazgos abiertos, se detiene y los hallazgos restantes se entregan como pendientes.

`audit.sh` se detiene y **conserva el avance** en estos casos:

| Exit | Situacion |
|---|---|
| 10 | falta de acceso: sin login, o login por API key |
| 11 | limite de uso de ChatGPT alcanzado |
| 12 | error persistente de Codex o sin salida de red |
| 13 | arbol sucio: la revision auditada no seria exacta |

Ante un **desacuerdo sin resolver** entre Claude y Codex (Codex insiste en un hallazgo
que Claude considera incorrecto), el circuito se detiene y te lo eleva a vos con las dos
posiciones y la evidencia de cada una. No se resuelve solo.

---

## 6. Lo que le falta a Codex para auditar TCK bien

Codex **no hereda** nada de lo que tiene Claude. En concreto:

**No hereda la memoria de ChatGPT.** No conoce ninguna conversacion previa sobre TCK,
ni decisiones de diseno, ni tus preferencias. Todo lo que sepa del proyecto tiene que
estar en el repo o en el `--pedido`.

**No hereda los MCP de Claude.** En esta sesion Claude tiene Supabase, GitHub, Slack,
Google Drive y Figma. Codex arranca sin ninguno, asi que por defecto **no puede**:
consultar el esquema o los datos de Supabase, leer PRs o issues, ni abrir los disenos.
Si lo necesitas, Codex tiene su propio registro: `codex mcp` (ver `codex mcp --help`).
Configuralo aparte y de forma explicita.

**El repo no declara reglas de proyecto.** Hoy no existen `CLAUDE.md`, `AGENTS.md`,
`README.md` ni `CONTRIBUTING.md` en la raiz. Es el hueco mas grande del circuito: el
auditor no tiene ningun estandar escrito contra el cual medir, mas que el pedido puntual.
**Recomendacion:** crear un `AGENTS.md` (Codex lo lee de forma nativa) con convenciones,
estructura del catalogo, y que significa "listo" en este proyecto.

**El repo no tiene pruebas automaticas.** No hay `package.json` ni suite de tests para el
catalogo, asi que `AUDIT_TEST_CMD` no tiene nada que correr sobre TCK y el auditor no puede
apoyarse en evidencia ejecutable. Las pruebas del fixture en `smoke/` existen solo para
validar el circuito, no cubren el catalogo.

**Sin acceso a produccion, a proposito.** El auditor no ejecuta SQL ni toca datos reales.
Si un cambio depende del esquema de la base, hay que incluir el esquema relevante en el
`--pedido`, o darle a Codex su propio MCP de Supabase de solo lectura.
