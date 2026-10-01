import { describe, expect, it } from 'vitest';
import {
  centsToAmount,
  decimalStringToCents,
  formatCents,
  formatMoney,
  formatSignedCents,
  newTxId,
  parseBRLToCents,
} from '../money';

describe('formatCents', () => {
  it('formata centavos em pt-BR', () => {
    expect(formatCents(100000)).toBe('R$ 1.000,00');
    expect(formatCents(150)).toBe('R$ 1,50');
    expect(formatCents(0)).toBe('R$ 0,00');
    expect(formatCents(-250)).toBe('-R$ 2,50');
  });

  it('nunca usa float: 0.1+0.2 não vaza para a formatação', () => {
    // 10 + 20 cents = 30 cents exatos, sem erro de binário
    expect(formatCents(10 + 20)).toBe('R$ 0,30');
  });
});

describe('formatMoney', () => {
  it('aceita string decimal da API', () => {
    expect(formatMoney('1000.00')).toBe('R$ 1.000,00');
    expect(formatMoney('1.50')).toBe('R$ 1,50');
  });
  it('aceita centavos inteiros', () => {
    expect(formatMoney(9999)).toBe('R$ 99,99');
  });
});

describe('formatSignedCents', () => {
  it('prefixa sinal explícito', () => {
    expect(formatSignedCents(5000)).toBe('+R$ 50,00');
    expect(formatSignedCents(-5000)).toBe('−R$ 50,00');
    expect(formatSignedCents(0)).toBe('R$ 0,00');
  });
});

describe('centsToAmount', () => {
  it('gera string decimal exata para a API', () => {
    expect(centsToAmount(100000)).toBe('1000.00');
    expect(centsToAmount(150)).toBe('1.50');
    expect(centsToAmount(5)).toBe('0.05');
  });
});

describe('parseBRLToCents', () => {
  it('entende formato brasileiro', () => {
    expect(parseBRLToCents('1.250,50')).toBe(125050);
    expect(parseBRLToCents('1250,50')).toBe(125050);
    expect(parseBRLToCents('1.000')).toBe(100000);
    expect(parseBRLToCents('1000')).toBe(100000);
    expect(parseBRLToCents('0,05')).toBe(5);
  });
  it('aceita ponto como decimal quando não há vírgula', () => {
    expect(parseBRLToCents('1000.50')).toBe(100050);
  });
  it('rejeita entradas inválidas', () => {
    expect(parseBRLToCents('')).toBeNull();
    expect(parseBRLToCents('abc')).toBeNull();
    expect(parseBRLToCents('1,234')).toBeNull(); // 3 casas
    expect(parseBRLToCents('1.000,5,0')).toBeNull();
    expect(parseBRLToCents('-50')).toBeNull();
  });
  it('round-trip sem perda: parse -> centsToAmount', () => {
    for (const raw of ['1.250,50', '99,99', '1000000', '0,01']) {
      const cents = parseBRLToCents(raw);
      expect(cents).not.toBeNull();
      // converte de volta e compara centavos (sem float)
      const back = decimalStringToCents(centsToAmount(cents as number));
      expect(back).toBe(cents);
    }
  });
});

describe('newTxId', () => {
  it('gera ids únicos dentro do formato da API [A-Za-z0-9_-]{1,24}', () => {
    const ids = new Set(Array.from({ length: 100 }, () => newTxId()));
    expect(ids.size).toBe(100);
    for (const id of ids) {
      expect(id).toMatch(/^[A-Za-z0-9_-]{1,24}$/);
      expect(id.startsWith('WEB-')).toBe(true);
    }
  });
});
