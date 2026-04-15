export const EVENTS = [
  {
    value: 'reservation.confirmed',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_CONFIRMED',
  },
  {
    value: 'checkin.scheduled_at',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.CHECKIN_SCHEDULED_AT',
  },
  {
    value: 'checkout.scheduled_at',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.CHECKOUT_SCHEDULED_AT',
  },
  {
    value: 'reservation.cancelled',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_CANCELLED',
  },
  {
    value: 'reservation.no_show',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_NO_SHOW',
  },
];

export const MESSAGE_TYPES = [
  {
    value: 'text',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.TEXT',
  },
  {
    value: 'buttons',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.BUTTONS',
  },
  {
    value: 'list',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.LIST',
  },
  {
    value: 'url_button',
    labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.URL_BUTTON',
  },
];

export const OFFSET_UNITS = [
  { value: 'minutes', factor: 1 },
  { value: 'hours', factor: 60 },
  { value: 'days', factor: 1440 },
];

export const AVAILABLE_VARIABLES = [
  { key: 'customer.first_name', descKey: 'Primeiro nome do cliente' },
  { key: 'customer.name', descKey: 'Nome completo' },
  { key: 'customer.phone', descKey: 'Telefone' },
  { key: 'reservation.suite', descKey: 'Suíte' },
  { key: 'reservation.unit_name', descKey: 'Nome da unidade' },
  { key: 'reservation.check_in_at', descKey: 'Check-in' },
  { key: 'reservation.check_out_at', descKey: 'Check-out' },
  { key: 'reservation.amount', descKey: 'Valor' },
  { key: 'hotel.wifi_password', descKey: 'Senha do WiFi' },
  { key: 'hotel.menu_link', descKey: 'Link do cardápio' },
  { key: 'hotel.google_review_link', descKey: 'Link de review' },
  { key: 'hotel.address', descKey: 'Endereço' },
];

export const RULE_TEMPLATES = [
  {
    id: 'precheckin_reminder',
    name: 'Lembrete 10min antes do check-in',
    event: 'checkin.scheduled_at',
    offset_minutes: -10,
    message_type: 'text',
    message_body:
      'Oi {{ customer.first_name }}! Seu check-in é em 10 minutos na suíte {{ reservation.suite }}. Wifi: {{ hotel.wifi_password }}',
  },
  {
    id: 'welcome_instay',
    name: 'Boas-vindas após check-in',
    event: 'checkin.scheduled_at',
    offset_minutes: 15,
    message_type: 'text',
    message_body:
      'Seja bem-vindo(a), {{ customer.first_name }}! Qualquer coisa, só chamar. Cardápio: {{ hotel.menu_link }}',
  },
  {
    id: 'review_request',
    name: 'Pedido de review no Google',
    event: 'checkout.scheduled_at',
    offset_minutes: 120,
    message_type: 'url_button',
    message_body:
      '{{ customer.first_name }}, adoraríamos saber como foi sua estadia. Se puder, deixa um review pra gente: {{ hotel.google_review_link }}',
  },
];
