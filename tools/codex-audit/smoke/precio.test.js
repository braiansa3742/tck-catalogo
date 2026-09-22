'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { aplicarDescuento, totalCarrito } = require('./precio.js');

test('aplicarDescuento calcula un 20% correctamente', () => {
  assert.strictEqual(aplicarDescuento(1000, 20), 800);
});

test('totalCarrito suma TODOS los items del carrito', () => {
  const items = [
    { precio: 100, cantidad: 2 },
    { precio: 50, cantidad: 1 },
    { precio: 200, cantidad: 3 },
  ];
  assert.strictEqual(totalCarrito(items), 850);
});

test('totalCarrito con un solo item devuelve su subtotal', () => {
  assert.strictEqual(totalCarrito([{ precio: 999, cantidad: 1 }]), 999);
});
