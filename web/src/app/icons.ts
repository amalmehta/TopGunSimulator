// Small inline SVG icons (stroke-based, inherit currentColor).
const svg = (body: string) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`

export const icons = {
  back: svg('<path d="M15 18l-6-6 6-6"/>'),
  plane: svg('<path d="M12 3v18M4 11l8-2 8 2M8 19l4-1 4 1"/>'),
  eye: svg('<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  orbit: svg('<circle cx="12" cy="12" r="3"/><ellipse cx="12" cy="12" rx="10" ry="4"/>'),
  tower: svg('<path d="M9 21V9h6v12M7 9h10l-1-4H8zM5 21h14"/>'),
  pause: svg('<path d="M8 5v14M16 5v14"/>'),
  play: svg('<path d="M7 4l13 8-13 8z"/>'),
  restart: svg('<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>'),
  gauge: svg('<circle cx="12" cy="13" r="8"/><path d="M12 13l4-4"/>'),
  sidebar: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M15 4v16"/>'),
  keyboard: svg('<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>'),
  gear: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  check: svg('<path d="M20 6L9 17l-5-5"/>'),
  cap: svg('<path d="M22 10L12 5 2 10l10 5 10-5z"/><path d="M6 12v5c3 2 9 2 12 0v-5"/>'),
  person: svg('<circle cx="9" cy="7" r="4"/><path d="M3 21v-1a6 6 0 0 1 12 0v1M18 8a4 4 0 0 1 0 6M21 6a7 7 0 0 1 0 10"/>'),
  // Category symbols
  Basics: svg('<rect x="2" y="7" width="20" height="10" rx="5"/><path d="M7 10v4M5 12h4M16 11h.01M18 13h.01"/>'),
  Maneuvers: svg('<path d="M12 2l10 10-10 10L2 12z"/><path d="M9 14v-3h5M12 9l2 2-2 2"/>'),
  Takeoff: svg('<path d="M2 20h20M4 15l14-6 2 2-12 7z"/>'),
  Landing: svg('<path d="M2 20h20M4 9l12 6h4v-2L6 6z"/>'),
  'Low Level': svg('<path d="M2 20l7-12 4 6 3-4 6 10z"/>'),
  Dogfight: svg('<circle cx="12" cy="12" r="8"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>'),
}
