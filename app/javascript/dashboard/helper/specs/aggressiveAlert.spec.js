import { formatWaited } from '../aggressiveAlert';

const min = n => n * 60 * 1000;
const hour = n => n * 60 * min(1);

describe('formatWaited', () => {
  it('mostra "agora" abaixo de um minuto', () => {
    expect(formatWaited(0)).toBe('agora');
    expect(formatWaited(30 * 1000)).toBe('agora');
    expect(formatWaited(0, { nowLabel: 'just now' })).toBe('just now');
  });

  it('mostra minutos abaixo de uma hora', () => {
    expect(formatWaited(min(1))).toBe('1 min');
    expect(formatWaited(min(28))).toBe('28 min');
    expect(formatWaited(min(59))).toBe('59 min');
  });

  it('mostra horas — o caso que estava quebrado', () => {
    // Antes da correção, qualquer conversa acima de 28 minutos aparecia como
    // "28 min", inclusive as de horas. Era o que fazia a equipe despriorizar
    // justamente o caso mais grave.
    expect(formatWaited(hour(1))).toBe('1h');
    expect(formatWaited(hour(2))).toBe('2h');
    expect(formatWaited(hour(4) + min(30))).toBe('4h30');
    expect(formatWaited(hour(6))).toBe('6h');
    expect(formatWaited(hour(1) + min(5))).toBe('1h05');
  });

  it('mostra dias acima de 24h', () => {
    expect(formatWaited(hour(24))).toBe('1d');
    expect(formatWaited(hour(50))).toBe('2d');
  });

  it('não quebra com entrada inválida', () => {
    expect(formatWaited(null)).toBe('agora');
    expect(formatWaited(undefined)).toBe('agora');
    expect(formatWaited(-5000)).toBe('agora');
    expect(formatWaited('lixo')).toBe('agora');
  });
});
