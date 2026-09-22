'use strict';

// Version BASE del fixture: totalCarrito todavia no esta implementada.
// smoke.sh la usa como punto de partida para que el diff auditado
// contenga realmente el cambio que Codex debe revisar.

function aplicarDescuento(precio, porcentaje) {
  return precio - (precio * porcentaje) / 100;
}

function totalCarrito(items) {
  return 0; // TODO: implementar
}

module.exports = { aplicarDescuento, totalCarrito };
