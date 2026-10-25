// Original line-figure emblems for every catalogue exercise, drawn in a 48x48 box with currentColor so the map, the detail
// panel and the survey can tint them by state. Simple stick figures: head, torso, limbs, ground line.
const H = (x, y, r = 3.4) => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`;
const L = (...pts) => `<polyline points="${pts.join(' ')}"/>`;
const G = '<line x1="5" y1="41" x2="43" y2="41" opacity=".45"/>';

const FIGURES = {
  squat: H(19, 9) + L('19,13', '23,25', '33,26', '30,40') + L('20,16', '33,18') + G,
  gluteBridge: H(8, 34) + L('11,35', '23,26', '31,27', '34,40') + L('11,36', '19,40') + G,
  reverseLunge: H(22, 7) + L('22,11', '22,24') + L('22,24', '31,30', '31,40') + L('22,24', '14,33', '8,40') + L('22,14', '17,21') + G,
  splitSquat: H(22, 10) + L('22,14', '22,26') + L('22,26', '31,31', '31,40') + L('22,26', '13,35', '7,40') + L('22,17', '27,23') + G,
  assistedSquat: L('39,8', '39,40') + H(19, 10) + L('19,14', '22,25') + L('22,25', '30,27', '28,40') + L('22,25', '11,28') + L('20,17', '38,19') + G,
  wallPushup: L('8,5', '8,40') + H(15, 12) + L('17,15', '33,39') + L('19,17', '9,17') + G,
  inclinePushup: '<rect x="5" y="29" width="13" height="12" rx="1.5"/>' + H(13, 19) + L('16,21', '41,38') + L('18,22', '14,29') + G,
  kneePushup: H(10, 22) + L('13,24', '30,39', '41,37') + L('15,25', '15,40') + G,
  pushup: H(9, 21) + L('12,23', '41,37') + L('15,24', '15,40') + G,
  closeGripPushup: H(9, 21) + L('12,23', '41,37') + L('16,24', '18,40') + L('19,25', '21,40') + G,
  deadBug: H(7, 33) + L('10,34', '26,34') + L('13,34', '13,20') + L('17,34', '25,22') + L('26,34', '30,24', '37,24') + G,
  plank: H(9, 24) + L('12,26', '41,37') + L('13,27', '13,40', '21,40') + G,
  sidePlank: H(11, 11) + L('13,14', '39,38') + L('15,17', '15,40') + L('17,16', '19,5') + G,
  stepJack: H(24, 7) + L('24,11', '24,25') + L('24,25', '16,40') + L('24,25', '31,40') + L('24,14', '14,6') + L('24,14', '34,6') + G,
  highKnees: H(22, 7) + L('22,11', '23,25') + L('23,25', '24,40') + L('23,25', '32,26', '31,34') + L('22,14', '15,20') + L('22,14', '29,9') + G,
  mountainClimber: H(9, 19) + L('12,21', '41,36') + L('14,22', '14,40') + L('27,29', '20,33', '22,39') + G,
  catCow: H(9, 21) + '<path d="M12 24 Q24 13 35 24"/>' + L('13,24', '13,40') + L('35,24', '35,40', '41,40') + G,
  hipFlexorStretch: H(22, 7) + L('22,11', '23,25') + L('23,25', '31,27', '31,40') + L('23,25', '16,40', '7,40') + L('22,14', '27,21') + G,
  singleLegBalance: H(24, 7) + L('24,11', '24,25') + L('24,25', '24,40') + L('24,25', '31,29', '29,35') + L('24,14', '15,17') + L('24,14', '33,17') + G,
};

// SVG markup for an emblem, positioned in a square of `size` centred on (cx, cy) when nested in another SVG.
export function emblem(id, { size = 36, cx = 0, cy = 0, label = '' } = {}) {
  const body = FIGURES[id] ?? H(24, 12) + L('24,16', '24,30') + G;
  return `<svg x="${cx - size / 2}" y="${cy - size / 2}" width="${size}" height="${size}" viewBox="0 0 48 48" ${label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"'}><g fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">${body}</g></svg>`;
}
// A standalone inline emblem (for panels and survey tiles).
export const emblemInline = (id, size = 56, label = '') => `<svg class="emblem" width="${size}" height="${size}" viewBox="0 0 48 48" ${label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"'}><g fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">${FIGURES[id] ?? ''}</g></svg>`;

// Small UI icons (24x24, stroke).
const I = {
  camera: '<rect x="3" y="7" width="18" height="13" rx="2.5"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8.5 7 10 4.5h4L15.5 7"/>',
  count: '<path d="M5 18V8l3-2"/><path d="M11 9a3 3 0 1 1 6 0c0 2-6 4-6 9h6"/>',
  log: '<path d="M6 4h12v16H6z"/><path d="M9 9h6M9 13h6M9 17h3"/>',
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  star: '<path d="m12 4 2.4 5 5.4.6-4 3.7 1.1 5.3L12 16l-4.9 2.6 1.1-5.3-4-3.7 5.4-.6z"/>',
  skip: '<path d="M6 12h12M14 8l4 4-4 4"/>',
  target: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r=".8" fill="currentColor"/>',
  flag: '<path d="M6 21V4M6 4h11l-2 4 2 4H6"/>',
  wall: '<path d="M4 4v16M4 8h6M4 12h6M4 16h6"/><path d="M14 18l5-12"/>',
  table: '<path d="M3 9h18M6 9v10M18 9v10"/>',
  chair: '<path d="M7 3v18M7 12h10v9M17 12V8"/>',
  none: '<circle cx="12" cy="12" r="8"/><path d="m6.5 6.5 11 11"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  calendar: '<rect x="4" y="5.5" width="16" height="15" rx="2"/><path d="M4 10h16M9 3.5v4M15 3.5v4"/>',
  book: '<path d="M5 5.5A2.5 2.5 0 0 1 7.5 3H19v15H7.5A2.5 2.5 0 0 0 5 20.5z"/><path d="M5 20.5V5.5"/>',
  repeat: '<path d="M17 3l3 3-3 3"/><path d="M4 11V9a3 3 0 0 1 3-3h13"/><path d="M7 21l-3-3 3-3"/><path d="M20 13v2a3 3 0 0 1-3 3H4"/>',
  spark: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
  chat: '<path d="M5 5h14v10H9l-4 4z"/>',
  up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  down: '<path d="M12 5v14M6 13l6 6 6-6"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  route: '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M8 18h5a3 3 0 0 0 0-6h-2a3 3 0 0 1 0-6h5"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"/>',
  bolt: '<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>',
  doc: '<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/>',
};
export const icon = (name, size = 18) => `<svg class="ico" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${I[name] ?? ''}</g></svg>`;
