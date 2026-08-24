// Helpers portados da UI do Sinal (sinal-web) para as réplicas nativas.
// Datas chegam como 'YYYY-MM-DD' (dia local) ou ISO completo.

export function fmtDay(iso, withWeekday = false) {
  const d = new Date(`${iso}T00:00:00`);
  return d
    .toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      ...(withWeekday ? { weekday: 'short' } : {}),
    })
    .replace(/\./g, '');
}

export function timeAgo(iso) {
  if (!iso) return 'sem registro';
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 0) return 'agora';
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `há ${mins}min`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `há ${hrs}h`;
  const days = Math.floor(hrs / 24);
  return `há ${days}d`;
}

export function formatMinutes(min) {
  if (min === null || min === undefined) return '—';
  const rounded = Math.round(min);
  if (rounded < 60) return `${rounded}m`;
  const h = Math.floor(rounded / 60);
  const m = rounded % 60;
  return m === 0 ? `${h}h` : `${h}h${m.toString().padStart(2, '0')}`;
}

export function formatNumber(n) {
  return Number(n || 0).toLocaleString('pt-BR');
}

export function dateInputValue(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

export function monthInputValue(date = new Date()) {
  return dateInputValue(date).slice(0, 7);
}

export function monthEndDate(month) {
  const [year, monthNumber] = month.split('-').map(Number);
  if (!year || !monthNumber) return dateInputValue();
  return dateInputValue(new Date(year, monthNumber, 0));
}

export function periodDayBounds(date) {
  return {
    since: Math.floor(new Date(`${date}T00:00:00`) / 1000),
    until: Math.floor(new Date(`${date}T23:59:59`) / 1000),
  };
}

// Calcula o range em epoch (segundos) a partir do preset do SinalPeriodPicker.
// Precisa ser chamada de novo a cada fetch (nunca guardada num computed): para
// presets relativos (7/14/30 dias) o "agora" tem que ser o instante da
// chamada, senão o período congela no momento em que a página foi aberta.
export function computePeriodRange({ preset, customStart, customEnd }) {
  if (preset === 'today') {
    return periodDayBounds(dateInputValue());
  }
  if (preset === 'custom') {
    const today = dateInputValue();
    const first = customStart || today;
    const last = customEnd || today;
    const [start, end] = first <= last ? [first, last] : [last, first];
    return {
      since: periodDayBounds(start).since,
      until: periodDayBounds(end).until,
    };
  }
  const until = Math.floor(Date.now() / 1000);
  const days = Number(preset) || 7;
  return { since: until - days * 86400, until };
}

export function formatDateShort(date) {
  return new Date(`${date}T00:00:00`).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
}

export function formatMonthLabel(month) {
  const [year, monthNumber] = month.split('-').map(Number);
  if (!year || !monthNumber) return 'Mês';
  return new Date(year, monthNumber - 1, 1)
    .toLocaleDateString('pt-BR', { month: 'short', year: 'numeric' })
    .replace(/\./g, '');
}

export const SINAL_PALETTE = [
  'var(--accent)',
  '#60A5FA',
  '#A78BFA',
  '#F472B6',
  '#FBBF24',
  '#4ADE80',
];

// Cores fixas do card "Adoção do sistema" — painel reaproveita o amber já
// usado pra "humano" no resto da página; WhatsApp direto ganha uma cor à
// parte (fora do sistema, vale atenção). Compartilhadas entre
// SinalOverview.vue e SystemAdoptionCard.vue pra não divergir.
export const SYSTEM_ADOPTION_COLORS = {
  panel: '#FBBF24',
  whatsappDirect: '#F87171',
};
