#!/usr/bin/env bash
# Invoca a Codex (OpenAI) como auditor no interactivo de un cambio hecho por Claude Code.
#
# Garantias de diseno:
#   - Codex trabaja sobre un snapshot inmutable (git worktree en un SHA fijo):
#     Claude puede seguir editando el arbol principal sin alterar lo que se audita.
#   - Codex corre con sandbox read-only: puede leer y ejecutar, no puede editar.
#   - Nunca hace push, merge, ni toca bases de datos.
#   - No usa OPENAI_API_KEY (se desactiva por invocacion) ni escribe ~/.codex/config.toml.
#
# Uso: ./audit.sh --pedido <archivo> [--informe <archivo>] [--base <rama>] [--ronda N] [--out <dir>]
#
# Codigos de salida:
#   0  auditoria completada (ver findings.json para el veredicto)
#   2  error de uso
#   10 falta de acceso / sin login
#   11 limite de uso alcanzado
#   12 error persistente de Codex o de red
#   13 arbol de trabajo sucio (la revision no seria exacta)

set -uo pipefail

PEDIDO=""; INFORME=""; BASE="main"; RONDA="1"; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pedido)  PEDIDO="${2:-}"; shift 2 ;;
    --informe) INFORME="${2:-}"; shift 2 ;;
    --base)    BASE="${2:-}"; shift 2 ;;
    --ronda)   RONDA="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done

[ -n "$PEDIDO" ] || { echo "ERROR: falta --pedido <archivo con pedido, alcance y criterios de aceptacion>" >&2; exit 2; }
[ -f "$PEDIDO" ] || { echo "ERROR: no existe el archivo de pedido: $PEDIDO" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: no estas en un repo git." >&2; exit 2; }
cd "$REPO"

# ---------- 1. Preflight ----------
command -v codex >/dev/null 2>&1 || { echo "ERROR: Codex CLI no esta instalado. Ver README.md" >&2; exit 10; }
echo "Codex: $(codex --version)"

if ! LOGIN="$(codex login status 2>&1)"; then
  echo "ERROR: Codex no tiene sesion iniciada. Ejecuta 'codex login' (login con ChatGPT en el navegador)." >&2
  exit 10
fi
echo "Login: $LOGIN"
case "$(printf '%s' "$LOGIN" | tr 'A-Z' 'a-z')" in
  *"api key"*) echo "ERROR: Codex esta autenticado con API key. Este circuito requiere ChatGPT: 'codex logout' y luego 'codex login'." >&2; exit 10 ;;
esac
[ -n "${OPENAI_API_KEY:-}" ] && echo "AVISO: OPENAI_API_KEY esta en el entorno; se desactiva solo para esta invocacion."

RAMA="$(git rev-parse --abbrev-ref HEAD)"
case "$RAMA" in
  main|master) echo "ERROR: estas en '$RAMA'. Trabaja en una rama aislada antes de auditar." >&2; exit 2 ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: hay cambios sin commitear. Commiteá primero: la revision auditada debe ser exacta e inmutable." >&2
  git status --short >&2
  exit 13
fi

SHA="$(git rev-parse HEAD)"
SHA_CORTO="$(git rev-parse --short HEAD)"
git rev-parse --verify "$BASE" >/dev/null 2>&1 || { echo "ERROR: no existe la rama base '$BASE'." >&2; exit 2; }

OUT="${OUT:-$REPO/.codex-audit/ronda-$RONDA-$SHA_CORTO}"
mkdir -p "$OUT"

# ---------- 2. Snapshot inmutable ----------
WT="$(mktemp -d -t codex-audit-XXXXXX)"
cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git worktree add --detach --quiet "$WT" "$SHA" || { echo "ERROR: no se pudo crear el worktree del snapshot." >&2; exit 12; }
echo "Snapshot inmutable: $SHA_CORTO -> $WT"

# ---------- 3. Bundle de contexto ----------
DIFF="$OUT/cambios.diff"
git diff "$BASE...$SHA" > "$DIFF"
git diff --name-status "$BASE...$SHA" > "$OUT/archivos-cambiados.txt"

PRUEBAS="$OUT/pruebas.txt"
if [ -n "${AUDIT_TEST_CMD:-}" ]; then
  echo "\$ $AUDIT_TEST_CMD" > "$PRUEBAS"
  ( cd "$WT" && eval "$AUDIT_TEST_CMD" ) >> "$PRUEBAS" 2>&1
  echo "[exit=$?]" >> "$PRUEBAS"
else
  echo "(AUDIT_TEST_CMD no definido: Claude no ejecuto pruebas automaticas)" > "$PRUEBAS"
fi

BUNDLE="$OUT/bundle.md"
{
  cat "$HERE/prompt.md"
  echo; echo "---"; echo
  echo "## Identidad de la revision (NO cambia durante la auditoria)"
  echo "- Repositorio: $(basename "$REPO")"
  echo "- Rama: $RAMA"
  echo "- Base de comparacion: $BASE"
  echo "- SHA auditado: $SHA"
  echo "- Ronda: $RONDA de 3"
  echo "- Snapshot de solo lectura montado en: $WT"
  echo; echo "## Pedido, alcance y criterios de aceptacion"; echo
  cat "$PEDIDO"
  echo; echo "## Informe de Claude Code"; echo
  if [ -n "$INFORME" ] && [ -f "$INFORME" ]; then cat "$INFORME"; else echo "(sin informe adjunto)"; fi
  echo; echo "## Reglas del proyecto"; echo
  FOUND=0
  for f in CLAUDE.md AGENTS.md REVIEW.md CONTRIBUTING.md; do
    if [ -f "$WT/$f" ]; then echo "### $f"; echo '```'; cat "$WT/$f"; echo '```'; FOUND=1; fi
  done
  [ "$FOUND" = 0 ] && echo "(el repo no define reglas en CLAUDE.md/AGENTS.md/REVIEW.md/CONTRIBUTING.md)"
  echo; echo "## Archivos cambiados"; echo '```'; cat "$OUT/archivos-cambiados.txt"; echo '```'
  echo; echo "## Diff real ($BASE...$SHA)"; echo '```diff'; cat "$DIFF"; echo '```'
  echo; echo "## Contenido completo de los archivos cambiados (en el SHA auditado)"
  echo "El diff solo muestra el cambio; esto te da el contexto alrededor."
  git diff --name-only --diff-filter=d "$BASE...$SHA" | while IFS= read -r f; do
    [ -f "$WT/$f" ] || continue
    SZ=$(wc -c < "$WT/$f")
    echo; echo "### $f"
    if [ "$SZ" -gt 60000 ]; then
      echo "(archivo de $SZ bytes: omitido por tamano. Leelo desde el snapshot si lo necesitas: $f)"
    else
      echo '```'; cat -n "$WT/$f"; echo '```'
    fi
  done
  echo; echo "## Resultado de pruebas ejecutado por Claude"; echo '```'; cat "$PRUEBAS"; echo '```'
} > "$BUNDLE"
echo "Bundle: $BUNDLE ($(wc -c < "$BUNDLE") bytes)"

# ---------- 4. Auditoria ----------
FINDINGS="$OUT/findings.json"
LOG="$OUT/codex.log"
set +e
env -u OPENAI_API_KEY codex exec \
  -C "$WT" \
  -s read-only \
  --output-schema "$HERE/findings.schema.json" \
  -o "$FINDINGS" \
  - < "$BUNDLE" > "$LOG" 2>&1
CODE=$?
set -e

LOG_LC="$(tr 'A-Z' 'a-z' < "$LOG")"
case "$LOG_LC" in
  *"usage limit"*|*"rate limit"*|*"429"*|*"quota"*)
      echo "DETENIDO: limite de uso de ChatGPT alcanzado. Avance conservado en $OUT" >&2; exit 11 ;;
  *"not logged in"*|*"401"*|*"unauthorized"*)
      echo "DETENIDO: falta de acceso / sesion invalida. Avance conservado en $OUT" >&2; exit 10 ;;
esac
case "$LOG_LC" in
  *"connect failed"*|*"waiting for network"*|*"403"*)
      echo "DETENIDO: sin salida de red hacia OpenAI (proxy/firewall lo bloquea). Avance conservado en $OUT" >&2; exit 12 ;;
esac

if [ "$CODE" -ne 0 ] || [ ! -s "$FINDINGS" ]; then
  echo "DETENIDO: Codex fallo (exit=$CODE) o no produjo hallazgos. Revisa $LOG" >&2
  exit 12
fi

python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FINDINGS" 2>/dev/null \
  || { echo "AVISO: findings.json no es JSON valido; revisalo a mano en $FINDINGS" >&2; exit 12; }

# ---------- 5. Resultado ----------
SHA_POST="$(git rev-parse HEAD)"
[ "$SHA_POST" = "$SHA" ] || echo "AVISO: HEAD cambio durante la auditoria; el veredicto corresponde a $SHA_CORTO."

echo
echo "=== Auditoria de $SHA_CORTO (ronda $RONDA/3) ==="
python3 - "$FINDINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("Veredicto:", d.get("veredicto"))
print("Resumen:", d.get("resumen", "")[:500])
h = d.get("hallazgos", []); o = d.get("sugerencias_opcionales", []); b = d.get("bloqueos", [])
print(f"\nHallazgos bloqueantes: {len(h)}")
for f in h:
    print(f"  [{f.get('severidad')}] {f.get('archivo')}:{f.get('ubicacion')} - {f.get('descripcion')}")
    print(f"      impacto: {f.get('impacto')}")
    print(f"      evidencia: {f.get('evidencia')}")
print(f"\nSugerencias opcionales (no bloquean): {len(o)}")
for s in o:
    print(f"  - {s.get('archivo')}:{s.get('ubicacion')} - {s.get('sugerencia')}")
p = d.get("pruebas", {})
print(f"\nPruebas: {p.get('evaluacion')} - {p.get('comentarios','')}")
for x in p.get("faltantes", []): print(f"  falta: {x}")
if b:
    print("\nContexto/acceso que falto:")
    for x in b: print(f"  - {x}")
PY
echo
echo "Evidencia completa en: $OUT"
[ "$RONDA" -ge 3 ] && echo "AVISO: ronda 3 de 3. Si quedan hallazgos, detene el circuito y reportalos como pendientes."
exit 0
