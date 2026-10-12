// Six-pack gauges and the stick-vs-surface readout (port of InstrumentPanel.swift).
import { clamp } from '../core/math'
import type { AircraftSpec } from '../core/aircraft'
import type { Telemetry } from '../core/telemetry'
import { prepCanvas } from './frame'

type Ctx = CanvasRenderingContext2D

class Dial {
  c: { x: number; y: number }; r: number
  constructor(public ctx: Ctx, w: number, h: number) { this.c = { x: w / 2, y: h / 2 }; this.r = Math.min(w, h) / 2 - 4 }
  /** 0° = 12 o'clock, clockwise. */
  pt(a: number, radius: number) { const t = ((a - 90) * Math.PI) / 180; return [this.c.x + Math.cos(t) * radius, this.c.y + Math.sin(t) * radius] as const }
  face() {
    const { ctx } = this
    ctx.fillStyle = '#0d0d0d'; ctx.beginPath(); ctx.arc(this.c.x, this.c.y, this.r + 2, 0, Math.PI * 2); ctx.fill()
    ctx.strokeStyle = '#595959'; ctx.lineWidth = 3; ctx.stroke()
  }
  needle(a: number, len: number, width = 3, color = '#fff') {
    const { ctx } = this
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = 'round'
    ctx.beginPath(); ctx.moveTo(...this.pt(a + 180, this.r * 0.12)); ctx.lineTo(...this.pt(a, len)); ctx.stroke()
    ctx.fillStyle = '#4d4d4d'; ctx.beginPath(); ctx.arc(this.c.x, this.c.y, 4, 0, Math.PI * 2); ctx.fill()
  }
  arc(a0: number, a1: number, radius: number, color: string, width: number) {
    const { ctx } = this
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = 'butt'
    ctx.beginPath(); ctx.arc(this.c.x, this.c.y, radius, ((a0 - 90) * Math.PI) / 180, ((a1 - 90) * Math.PI) / 180); ctx.stroke()
  }
  tick(a: number, r0: number, r1: number, width = 1.5, color = '#fff') {
    const { ctx } = this
    ctx.strokeStyle = color; ctx.lineWidth = width
    ctx.beginPath(); ctx.moveTo(...this.pt(a, r0)); ctx.lineTo(...this.pt(a, r1)); ctx.stroke()
  }
  label(s: string, x: number, y: number, size = 9) {
    const { ctx } = this
    ctx.fillStyle = '#fff'; ctx.font = `600 ${size}px ui-rounded, system-ui, sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
    ctx.fillText(s, x, y)
  }
}

function airspeed(d: Dial, kt: number, spec: AircraftSpec) {
  const max = spec.vNeKt * 1.15
  const ang = (v: number) => clamp(v / max, 0, 1) * 320
  d.arc(ang(spec.vStallKt * 0.9), ang(spec.vApproachKt * 1.4), d.r * 0.78, '#fff', 3)
  d.arc(ang(spec.vStallKt), ang(spec.vCruiseKt * 1.15), d.r * 0.86, '#34c759', 4)
  d.arc(ang(spec.vCruiseKt * 1.15), ang(spec.vNeKt), d.r * 0.86, '#ffd60a', 4)
  d.arc(ang(spec.vNeKt), ang(spec.vNeKt) + 2, d.r * 0.86, '#ff3b30', 8)
  const step = spec.isJet ? 200 : 40
  for (let v = 0; v <= max; v += step) d.label(`${v}`, ...d.pt(ang(v), d.r * 0.62))
  d.label('KNOTS', d.c.x, d.c.y + d.r * 0.3, 7)
  d.needle(ang(kt), d.r * 0.85)
}

function attitude(d: Dial, pitch: number, bank: number) {
  const { ctx, c, r } = d
  const ppd = r / 30
  ctx.save()
  ctx.beginPath(); ctx.arc(c.x, c.y, r, 0, Math.PI * 2); ctx.clip()
  ctx.translate(c.x, c.y); ctx.rotate((-bank * Math.PI) / 180)
  const hy = pitch * ppd
  ctx.fillStyle = '#3380e6'; ctx.fillRect(-r * 2, -r * 4 + hy, r * 4, r * 4)
  ctx.fillStyle = '#8c592e'; ctx.fillRect(-r * 2, hy, r * 4, r * 4)
  ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(-r * 2, hy); ctx.lineTo(r * 2, hy); ctx.stroke()
  ctx.lineWidth = 1
  for (const p of [-20, -10, 10, 20]) { const y = hy - p * ppd; ctx.beginPath(); ctx.moveTo(-r * 0.25, y); ctx.lineTo(r * 0.25, y); ctx.stroke() }
  ctx.restore()
  for (const b of [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]) d.tick(b, r * 0.88, r * (Math.abs(b) % 30 === 0 ? 0.75 : 0.8))
  ctx.fillStyle = '#ff9500'
  ctx.beginPath(); ctx.moveTo(...d.pt(-bank, r * 0.74)); ctx.lineTo(...d.pt(-bank - 5, r * 0.62)); ctx.lineTo(...d.pt(-bank + 5, r * 0.62)); ctx.fill()
  ctx.strokeStyle = '#ff9500'; ctx.lineWidth = 3; ctx.lineJoin = 'round'
  ctx.beginPath(); ctx.moveTo(c.x - r * 0.5, c.y); ctx.lineTo(c.x - r * 0.15, c.y); ctx.lineTo(c.x, c.y + r * 0.1); ctx.lineTo(c.x + r * 0.15, c.y); ctx.lineTo(c.x + r * 0.5, c.y); ctx.stroke()
}

function altimeter(d: Dial, ft: number) {
  for (let i = 0; i < 10; i++) { d.label(`${i}`, ...d.pt(i * 36, d.r * 0.72), 10); d.tick(i * 36, d.r * 0.95, d.r * 0.85) }
  d.label(`${Math.round(ft)}`, d.c.x, d.c.y + d.r * 0.42, 8)
  d.needle(((ft / 10000) % 1) * 360, d.r * 0.35, 2, '#bfbfbf')
  d.needle(((ft / 1000) % 1) * 360, d.r * 0.5, 4)
  d.needle(((ft / 100) % 10) * 36, d.r * 0.85, 2)
}

function turnCoordinator(d: Dial, rate: number, slip: number) {
  const { ctx, c, r } = d
  for (const a of [-90, 90, -70, 110]) d.tick(a, r * 0.92, r * 0.78, 2)
  d.label('L', ...d.pt(-70, r * 0.62)); d.label('R', ...d.pt(70, r * 0.62))
  ctx.save(); ctx.translate(c.x, c.y - r * 0.05); ctx.rotate((clamp((rate / 3) * 20, -40, 40) * Math.PI) / 180)
  ctx.strokeStyle = '#fff'; ctx.lineWidth = 3; ctx.lineCap = 'round'
  ctx.beginPath(); ctx.moveTo(-r * 0.7, 0); ctx.lineTo(r * 0.7, 0); ctx.moveTo(0, 0); ctx.lineTo(0, -r * 0.18); ctx.stroke()
  ctx.restore()
  const ty = c.y + r * 0.35
  ctx.fillStyle = '#333'; ctx.beginPath(); ctx.roundRect(c.x - r * 0.5, ty, r, r * 0.2, r * 0.1); ctx.fill()
  const bx = c.x + clamp(-slip / 10, -1, 1) * r * 0.4
  ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(bx, ty + r * 0.1, r * 0.09, 0, Math.PI * 2); ctx.fill()
  ctx.strokeStyle = '#ff9500'; ctx.lineWidth = 1
  for (const x of [c.x - r * 0.11, c.x + r * 0.11]) { ctx.beginPath(); ctx.moveTo(x, ty); ctx.lineTo(x, ty + r * 0.2); ctx.stroke() }
}

function headingIndicator(d: Dial, heading: number) {
  const { ctx, c, r } = d
  for (let i = 0; i < 36; i++) {
    const a = i * 10 - heading
    d.tick(a, r * 0.95, r * (i % 3 === 0 ? 0.8 : 0.87), 1.2)
    if (i % 3 === 0) d.label(({ 0: 'N', 9: 'E', 18: 'S', 27: 'W' } as Record<number, string>)[i] ?? `${i}`, ...d.pt(a, r * 0.65), 10)
  }
  ctx.strokeStyle = '#ff9500'; ctx.lineWidth = 2.5; ctx.lineCap = 'round'
  ctx.beginPath()
  ctx.moveTo(c.x, c.y - r * 0.35); ctx.lineTo(c.x, c.y + r * 0.3)
  ctx.moveTo(c.x - r * 0.25, c.y - r * 0.05); ctx.lineTo(c.x + r * 0.25, c.y - r * 0.05)
  ctx.moveTo(c.x - r * 0.1, c.y + r * 0.25); ctx.lineTo(c.x + r * 0.1, c.y + r * 0.25)
  ctx.stroke()
  ctx.fillStyle = '#ff9500'; ctx.beginPath(); ctx.moveTo(...d.pt(0, r)); ctx.lineTo(...d.pt(-5, r * 0.88)); ctx.lineTo(...d.pt(5, r * 0.88)); ctx.fill()
}

function vsi(d: Dial, fpm: number, scale: number) {
  const ang = (v: number) => -90 + clamp(v / scale, -1, 1) * 170
  for (let i = -4; i <= 4; i++) {
    const v = (i * scale) / 4
    d.tick(ang(v), d.r * 0.95, d.r * 0.82)
    d.label(`${Math.abs(Math.trunc(v / 100))}`, ...d.pt(ang(v), d.r * 0.66))
  }
  d.label('UP', d.c.x + d.r * 0.15, d.c.y - d.r * 0.25, 7)
  d.label('DN', d.c.x + d.r * 0.15, d.c.y + d.r * 0.25, 7)
  d.needle(ang(fpm), d.r * 0.85)
}

/** Draws all six gauges into the panel's canvases. */
export function drawInstruments(canvases: HTMLCanvasElement[], t: Telemetry, spec: AircraftSpec) {
  const draws: ((d: Dial) => void)[] = [
    d => airspeed(d, t.airspeedKt, spec),
    d => attitude(d, t.pitchDeg, t.bankDeg),
    d => altimeter(d, t.altitudeFt),
    d => turnCoordinator(d, t.turnRateDegPerSec, t.slipDeg),
    d => headingIndicator(d, t.headingDeg),
    d => vsi(d, t.verticalSpeedFpm, spec.isJet ? 6000 : 2000),
  ]
  canvases.forEach((cv, i) => {
    const { ctx, w, h } = prepCanvas(cv)
    const d = new Dial(ctx, w, h)
    d.face()
    draws[i](d)
  })
}

/** Stick vs. surface boxes, rudder bar and power column. */
export function drawControls(canvas: HTMLCanvasElement, t: Telemetry) {
  const { ctx, w, h } = prepCanvas(canvas)
  const box = (x: number, title: string, px: number, py: number, color: string) => {
    const s = Math.min(62, h - 40)
    ctx.fillStyle = '#999'; ctx.font = '9px system-ui'; ctx.textAlign = 'center'; ctx.fillText(title, x + s / 2, 9)
    ctx.fillStyle = '#262626'; ctx.beginPath(); ctx.roundRect(x, 14, s, s, 4); ctx.fill()
    ctx.strokeStyle = '#4d4d4d'; ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(x, 14 + s / 2); ctx.lineTo(x + s, 14 + s / 2); ctx.moveTo(x + s / 2, 14); ctx.lineTo(x + s / 2, 14 + s); ctx.stroke()
    ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x + s / 2 + px * s * 0.45, 14 + s / 2 + py * s * 0.45, 5, 0, Math.PI * 2); ctx.fill()
    return s
  }
  const s = box(0, 'Stick', t.stickRoll, -t.stickPitch, '#fff')
  box(s + 10, 'Surfaces', t.aileron, -t.elevator, '#ff9500')
  const px = 2 * s + 26
  ctx.fillStyle = '#999'; ctx.fillText('Power', px + 7, 9)
  ctx.fillStyle = '#333'; ctx.fillRect(px, 14, 14, s)
  ctx.fillStyle = t.afterburner ? '#ff9500' : '#34c759'; ctx.fillRect(px, 14 + s * (1 - t.throttle), 14, s * t.throttle)
  const by = 14 + s + 10, bw = w - 44
  ctx.fillStyle = '#999'; ctx.textAlign = 'left'; ctx.fillText('Rudder', 0, by + 5)
  ctx.fillStyle = '#333'; ctx.fillRect(44, by, bw, 10)
  const mid = 44 + bw / 2
  for (const [v, color, hh] of [[t.rudder, '#fff', 10], [t.rudderSurface, '#ff9500', 4.5]] as const) {
    const x = mid + clamp(v, -1, 1) * bw / 2
    ctx.fillStyle = color; ctx.fillRect(Math.min(mid, x), by + (10 - hh) / 2, Math.abs(x - mid), hh)
  }
}
