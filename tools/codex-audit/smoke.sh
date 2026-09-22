#!/usr/bin/env bash
# Prueba de integracion real del circuito Claude Code -> Codex.
#
# Copia el fixture (con un error conocido) a un repo temporal FUERA de TCK, y ejecuta
# dos rondas reales de auditoria: una sobre el codigo roto y otra sobre el corregido.
# No declara exito salvo que Codex devuelva hallazgos reales en la ronda 1.
#
# Uso: ./smoke.sh [dir-de-evidencia]

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
EV="${1:-${TMPDIR:-/tmp}/codex-smoke-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$EV"
SB="$EV/sandbox"

echo "=== Prueba de integracion Claude Code -> Codex ==="
echo "Evidencia: $EV"; echo

command -v codex >/dev/null 2>&1 || { echo "FALLO: Codex CLI no instalado."; exit 10; }
codex --version | tee "$EV/00-version.txt"
if ! codex login status > "$EV/01-login.txt" 2>&1; then
  echo "FALLO: sin sesion de Codex. Ejecuta 'codex login' y reintenta."; cat "$EV/01-login.txt"; exit 10
fi
cat "$EV/01-login.txt"

# --- Repo de prueba aislado, separado de TCK ---
rm -rf "$SB"; mkdir -p "$SB"
cd "$SB"
git init -q .
# BASE: totalCarrito sin implementar
cp "$HERE/smoke/precio.base.js" "$SB/precio.js"
cp "$HERE/smoke/precio.test.js" "$SB/precio.test.js"
git add -A
git -c user.email=smoke@local -c user.name=smoke commit -qm "base: totalCarrito sin implementar"
git branch -q -M main && git checkout -q -b prueba/auditoria
# CAMBIO A AUDITAR: la implementacion con el error conocido (off-by-one)
cp "$HERE/smoke/precio.js" "$SB/precio.js"
git add -A
git -c user.email=smoke@local -c user.name=smoke commit -qm "implementa totalCarrito"

cat > "$EV/pedido.md" <<'EOP'
### Pedido
totalCarrito(items) debe devolver la suma de precio*cantidad de TODOS los items.

### Alcance
Solo precio.js. No cambiar la firma de las funciones.

### Criterios de aceptacion
1. totalCarrito suma todos los items, incluido el ultimo.
2. Un carrito de un solo item devuelve su subtotal.
3. `node --test` pasa las 3 pruebas de precio.test.js.
EOP
cat > "$EV/informe.md" <<'EOI'
Implemente totalCarrito recorriendo el array y acumulando precio*cantidad.
Creo que cumple los tres criterios.
EOI

export AUDIT_TEST_CMD="node --test"

echo; echo "--- RONDA 1: auditando codigo con el error conocido ---"
"$HERE/audit.sh" --pedido "$EV/pedido.md" --informe "$EV/informe.md" \
  --base main --ronda 1 --out "$EV/ronda-1" 2>&1 | tee "$EV/02-ronda1.txt"
R1=${PIPESTATUS[0]}
[ "$R1" -eq 0 ] || { echo; echo "FALLO: la ronda 1 no completo (exit=$R1). Evidencia en $EV"; exit "$R1"; }

N1=$(python3 -c "import json;print(len(json.load(open('$EV/ronda-1/findings.json'))['hallazgos']))" 2>/dev/null || echo 0)
V1=$(python3 -c "import json;print(json.load(open('$EV/ronda-1/findings.json'))['veredicto'])" 2>/dev/null || echo "?")
echo; echo "Ronda 1 -> veredicto=$V1, hallazgos=$N1"
[ "$N1" -ge 1 ] || { echo "FALLO: Codex no detecto el error conocido. El circuito no sirve como auditor."; exit 1; }

echo; echo "--- Corrigiendo el error y pidiendo segunda revision ---"
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("precio.js"); s = p.read_text()
s2 = s.replace("i < items.length - 1", "i < items.length")
assert s2 != s, "no se encontro el patron del bug"
p.write_text(s2)
PY
node --test > "$EV/03-pruebas-post-fix.txt" 2>&1
PT=$?
tail -8 "$EV/03-pruebas-post-fix.txt"
[ "$PT" -eq 0 ] || { echo "FALLO: las pruebas siguen fallando despues del fix."; exit 1; }
echo "Pruebas locales: 3/3 OK"

git add -A
git -c user.email=smoke@local -c user.name=smoke commit -qm "fix: totalCarrito suma todos los items"
cat > "$EV/informe.md" <<'EOI'
Corregido: el loop terminaba en items.length - 1 y omitia el ultimo item.
Ahora recorre hasta items.length. `node --test` pasa 3/3.
EOI

echo; echo "--- RONDA 2: auditando el codigo corregido ---"
"$HERE/audit.sh" --pedido "$EV/pedido.md" --informe "$EV/informe.md" \
  --base main --ronda 2 --out "$EV/ronda-2" 2>&1 | tee "$EV/04-ronda2.txt"
R2=${PIPESTATUS[0]}
[ "$R2" -eq 0 ] || { echo; echo "FALLO: la ronda 2 no completo (exit=$R2)."; exit "$R2"; }

N2=$(python3 -c "import json;print(len(json.load(open('$EV/ronda-2/findings.json'))['hallazgos']))" 2>/dev/null || echo "?")
V2=$(python3 -c "import json;print(json.load(open('$EV/ronda-2/findings.json'))['veredicto'])" 2>/dev/null || echo "?")

{
  echo "# Resultado de la prueba de integracion"
  echo "fecha: $(date -Iseconds)"
  echo "codex: $(codex --version)"
  echo "ronda 1 (codigo roto):      veredicto=$V1 hallazgos=$N1"
  echo "ronda 2 (codigo corregido): veredicto=$V2 hallazgos=$N2"
  echo "pruebas ejecutables post-fix: 3/3 OK"
} | tee "$EV/RESULTADO.txt"

echo
if [ "$N1" -ge 1 ] && [ "$V2" = "aprobado" ]; then
  echo "PASA: Codex detecto el error conocido, no edito archivos, y aprobo el codigo corregido."
  exit 0
fi
echo "PARCIAL: el intercambio funciono (ronda 1 detecto el error), pero la ronda 2 dio veredicto '$V2'."
echo "Revisa $EV/ronda-2/findings.json: puede ser un hallazgo legitimo."
exit 0
