// Fighter-style head-up display on a 2D canvas (port of HUDView.swift).
import { headingDelta, wrap360, deg, Units } from '../core/math'
import type { AircraftSpec } from '../core/aircraft'
import type { CameraMode } from './world'
import { prepCanvas, type Frame } from './frame'
import { fmt } from './settings'
import { touchText } from './touch'

const GREEN = '#59ff73', WARN = '#ff4d40', BANDIT = '#ff4040', GATE = '#ff9e1a'

export function drawHUD(canvas: HTMLCanvasElement, f: Frame, spec: AircraftSpec, camera: CameraMode, fov: number, bottomInset = 0) {
  const { ctx, w, h } = prepCanvas(canvas)
  const t = f.telemetry
  const c = { x: w / 2, y: h / 2 }
  const ppd = h / fov
  ctx.shadowColor = 'rgba(0,0,0,0.85)'
  ctx.shadowBlur = 3
  ctx.lineCap = 'round'

  const text = (s: string, x: number, y: number, o: { align?: CanvasTextAlign; color?: string; size?: number } = {}) => {
    ctx.font = `600 ${o.size ?? 13}px ui-monospace, SFMono-Regular, Menlo, monospace`
    ctx.fillStyle = o.color ?? GREEN
    ctx.textAlign = o.align ?? 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(s, x, y)
  }
  const line = (pts: [number, number][], color = GREEN, width = 1.6, dash: number[] = []) => {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.setLineDash(dash)
    ctx.beginPath(); pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y))); ctx.stroke()
    ctx.setLineDash([])
  }

  if (camera === 'Cockpit') {
    ctx.save()
    ctx.translate(c.x, c.y)
    ctx.rotate((-t.bankDeg * Math.PI) / 180)
    for (let d = -90; d <= 90; d += 5) {
      const y = (t.pitchDeg - d) * ppd
      if (Math.abs(y) > h * 0.42) continue
      const lw = d === 0 ? w * 0.35 : d % 10 === 0 ? 90 : 40
      const gap = d === 0 ? 40 : 30
      line([[-lw, y], [-gap, y]], GREEN, 1.4, d < 0 ? [8, 6] : [])
      line([[gap, y], [lw, y]], GREEN, 1.4, d < 0 ? [8, 6] : [])
      if (d !== 0 && d % 10 === 0) { text(`${Math.abs(d)}`, lw + 16, y); text(`${Math.abs(d)}`, -lw - 16, y) }
    }
    ctx.restore()
    const fx = c.x + t.slipDeg * ppd, fy = c.y + t.alphaDeg * ppd
    if (Math.abs(fx - c.x) < w / 2 && Math.abs(fy - c.y) < h / 2) {
      ctx.strokeStyle = GREEN; ctx.lineWidth = 2
      ctx.beginPath(); ctx.arc(fx, fy, 7, 0, Math.PI * 2); ctx.stroke()
      line([[fx - 20, fy], [fx - 7, fy]], GREEN, 2); line([[fx + 7, fy], [fx + 20, fy]], GREEN, 2); line([[fx, fy - 7], [fx, fy - 15]], GREEN, 2)
    }
    line([[c.x - 26, c.y], [c.x - 12, c.y], [c.x - 6, c.y + 8], [c.x, c.y], [c.x + 6, c.y + 8], [c.x + 12, c.y], [c.x + 26, c.y]])
  }

  // Heading tape
  const ty = 26
  const base = Math.floor(Math.round(t.headingDeg) / 5) * 5
  for (let off = -30; off <= 30; off += 5) {
    const hdg = base + off
    const x = c.x + (hdg - t.headingDeg) * 6
    const major = hdg % 10 === 0
    line([[x, ty], [x, ty + (major ? 10 : 5)]], GREEN, 1.2)
    if (major) {
      const hh = ((hdg % 360) + 360) % 360
      const label = ({ 0: 'N', 90: 'E', 180: 'S', 270: 'W' } as Record<number, string>)[hh] ?? String(hh / 10).padStart(2, '0')
      text(label, x, ty + 22, { size: 11 })
    }
  }
  line([[c.x - 6, ty - 8], [c.x, ty - 1], [c.x + 6, ty - 8]], GREEN, 2)
  text(`${String(Math.round(t.headingDeg) % 360).padStart(3, '0')}°`, c.x, ty + 40, { size: 15 })

  // Speed and altitude boxes. With on-screen touch controls they sit higher, clear of the controls.
  // In portrait the lesson strip sits under the heading tape, so the boxes go below it.
  const by = bottomInset > 0 ? Math.max(h > w ? 160 : 90, (h - bottomInset) / 2) : c.y
  const lx = c.x - Math.min(w * 0.32, 340), rx = c.x + Math.min(w * 0.32, 340)
  for (const [x, value, label] of [[lx, fmt.speed(t.airspeedKt), 'IAS'], [rx, fmt.altitude(t.altitudeFt), 'ALT']] as const) {
    ctx.strokeStyle = GREEN; ctx.lineWidth = 1.6
    ctx.beginPath(); ctx.roundRect(x - 58, by - 16, 116, 32, 4); ctx.stroke()
    text(value, x, by, { size: 17 })
    text(label, x, by - 28, { size: 11 })
  }
  text(fmt.vertical(t.verticalSpeedFpm), rx, by + 32)
  text('AGL ' + fmt.altitude(t.aglFt), rx, by + 50, { size: 12 })
  text(`G ${t.gLoad.toFixed(1)}`, lx, by + 32)
  text(`α ${t.alphaDeg.toFixed(1)}°`, lx, by + 50, { size: 12, color: t.stallMargin < 0.2 ? WARN : GREEN })
  if (spec.isJet) text(`M ${(t.airspeedKt * Units.knot / 340).toFixed(2)}`, lx, by + 68, { size: 12 })
  if (t.airspeedKt < spec.vStallKt * 1.15 && !t.onGround) text('SPEED', lx, by - 48, { color: WARN })

  // Systems strip
  // Systems strip: bottom-left normally, top-left (under the heading tape) with touch controls.
  const top = bottomInset > 0
  const sy = top ? 14 : h - 70
  const rowStep = top ? 16 : -20
  let sys = `THR ${Math.round(t.throttle * 100)}%`
  if (t.afterburner) sys += ' AB'
  sys += `   FLAPS ${Math.round(t.flapsDeg)}°`
  if (spec.hasRetractableGear) sys += t.gearDown ? '   GEAR DN' : '   GEAR UP'
  sys += `   TRIM ${t.trim >= 0 ? '+' : ''}${Math.round(t.trim * 100)}`
  if (t.brakes > 0) sys += '   BRK'
  text(sys, 18, sy, { align: 'left', size: 12 })

  // Combat and gate cues
  if (spec.isJet && f.banditPosition) {
    ctx.strokeStyle = GREEN; ctx.lineWidth = 1.2
    ctx.beginPath(); ctx.arc(c.x, c.y, 18, 0, Math.PI * 2); ctx.stroke()
    text(`GUN ${f.ammo}`, 18, sy + rowStep, { align: 'left', size: 12 })
    if (f.banditDistance !== null) text(`BANDIT ${(f.banditDistance / 1852).toFixed(1)} nm  ${Math.round(f.banditHealth)}%`, 18, sy + rowStep * 2, { align: 'left', size: 12, color: BANDIT })
    const p = f.banditScreen
    if (p && p.x > 20 && p.x < w - 20 && p.y > 20 && p.y < h - 20) {
      ctx.strokeStyle = BANDIT; ctx.lineWidth = 2; ctx.strokeRect(p.x - 16, p.y - 16, 32, 32)
      if (f.banditDistance !== null) text(`${Math.round(f.banditDistance)} m`, p.x, p.y + 28, { size: 11, color: BANDIT })
    } else if (f.banditHealth > 0) {
      const rel = f.banditPosition.sub(t.position)
      const bearing = headingDelta(wrap360(deg(Math.atan2(rel.x, -rel.z))), t.headingDeg)
      const elev = deg(Math.atan2(rel.y, Math.hypot(rel.x, rel.z)))
      const a = Math.atan2(-elev, bearing), r = Math.min(w, h) * 0.36
      ctx.save(); ctx.translate(c.x + Math.cos(a) * r, c.y + Math.sin(a) * r); ctx.rotate(a)
      ctx.fillStyle = BANDIT; ctx.beginPath(); ctx.moveTo(14, 0); ctx.lineTo(-8, -9); ctx.lineTo(-8, 9); ctx.closePath(); ctx.fill()
      ctx.restore()
    }
  }
  const g = f.nextGateScreen
  if (g && g.x > 0 && g.x < w && g.y > 0 && g.y < h) line([[g.x, g.y - 12], [g.x + 12, g.y], [g.x, g.y + 12], [g.x - 12, g.y], [g.x, g.y - 12]], GATE, 2)
  if (t.health < 100) text(`DAMAGE ${100 - Math.round(t.health)}%`, w - 18, sy, { align: 'right', size: 12, color: WARN })

  // Flashing warning banner
  const warning = f.hints.find(x => x.severity === 2)
  if (warning) {
    ctx.globalAlpha = Math.trunc(t.time * 3) % 2 === 0 ? 1 : 0.55
    text(bottomInset > 0 ? touchText(warning.text) : warning.text, c.x, h - 40 - bottomInset, { size: Math.min(22, w / 28), color: WARN })
    ctx.globalAlpha = 1
  }
}
