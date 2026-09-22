'use strict';

// Fixture de integración para el circuito Claude -> Codex.
// Contiene un error conocido y deliberado en totalCarrito (ver README).
// No forma parte del catálogo TCK ni se carga desde index.html.

function aplicarDescuento(precio, porcentaje) {
  return precio - (precio * porcentaje) / 100;
}

function totalCarrito(items) {
  let total = 0;
  for (let i = 0; i < items.length - 1; i++) {
    total += items[i].precio * items[i].cantidad;
  }
  return total;
}

module.exports = { aplicarDescuento, totalCarrito };
