// 2D moving map and side profile (port of MapViews.swift).
import { Terrain } from '../core/environment'
import { Vec3, clamp, headingDelta, rad } from '../core/math'
import { groundColor } from './world'
import { prepCanvas, type Frame } from './frame'
import { fmt } from './settings'

const B = { minX: -22_000, maxX: 22_000, minZ: -32_000, maxZ: 12_000 }
let terrainImage: HTMLCanvasElement | null = null

/** North-up shaded terrain image, rendered once. Row 0 is the northern edge (minZ). */
function terrain() {
  if (terrainImage) return terrainImage
  const px = 440
  const c = document.createElement('canvas'); c.width = px; c.height = px
  const g = c.getContext('2d')!
  const img = g.createImageData(px, px)
  const light = new Vec3(-0.6, 0.7, -0.4).normalized()
  for (let j = 0; j < px; j++) for (let i = 0; i < px; i++) {
    const x = B.minX + ((B.maxX - B.minX) * (i + 0.5)) / px
    const z = B.minZ + ((B.maxZ - B.minZ) * (j + 0.5)) / px
    const h = Terrain.height(x, z), n = Terrain.normal(x, z)
    const col = groundColor(h, 1 - n.y, x, z)
    const shade = 0.75 + 0.45 * n.dot(light)
    const k = (j * px + i) * 4
    img.data[k] = clamp(col[0] * shade, 0, 1) * 255
    img.data[k + 1] = clamp(col[1] * shade, 0, 1) * 255
    img.data[k + 2] = clamp(col[2] * shade, 0, 1) * 255
    img.data[k + 3] = 255
  }
  g.putImageData(img, 0, 0)
  terrainImage = c
  return c
}

export function drawMap(canvas: HTMLCanvasElement, f: Frame, metersPerPoint: number) {
  const { ctx, w, h } = prepCanvas(canvas)
  const me = f.telemetry.position, s = metersPerPoint
  const cx = w / 2, cy = h / 2
  const pt = (x: number, z: number) => [cx + (x - me.x) / s, cy + (z - me.z) / s] as const

  ctx.fillStyle = '#6e8f55'; ctx.fillRect(0, 0, w, h)
  const [tlx, tly] = pt(B.minX, B.minZ), [brx, bry] = pt(B.maxX, B.maxZ)
  ctx.imageSmoothingEnabled = true
  ctx.drawImage(terrain(), tlx, tly, brx - tlx, bry - tly)

  const [rx] = pt(-Terrain.runwayWidth / 2, 0), [, ry] = pt(0, Terrain.runwayNorthEnd)
  ctx.fillStyle = '#333'; ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 0.8
  ctx.fillRect(rx, ry, Math.max(Terrain.runwayWidth / s, 2), Terrain.runwayLength / s)
  ctx.strokeRect(rx, ry, Math.max(Terrain.runwayWidth / s, 2), Terrain.runwayLength / s)

  for (const g of f.gates) {
    const [x, y] = pt(g.center.x, g.center.z), r = Math.max(g.radius / s, 3)
    ctx.strokeStyle = g.status === 'passed' ? '#30d158' : g.status === 'missed' ? '#8e8e93' : '#ff9e1a'; ctx.lineWidth = 2
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke()
  }
  const poly = (pts: Vec3[], color: string, width: number, dash: number[] = []) => {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.setLineDash(dash)
    ctx.beginPath(); pts.forEach((v, i) => { const [x, y] = pt(v.x, v.z); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y) }); ctx.stroke()
    ctx.setLineDash([])
  }
  poly([...f.trail, me], 'rgba(255,255,255,0.8)', 1.5, [4, 3])
  if (f.banditPosition) {
    poly([...f.banditTrail, f.banditPosition], 'rgba(255,64,64,0.7)', 1.2)
    plane(ctx, ...pt(f.banditPosition.x, f.banditPosition.z), f.banditHeading, '#ff4040')
  }
  plane(ctx, cx, cy, f.telemetry.headingDeg, '#ffd60a')

  const bar = [100, 250, 500, 1000, 2000, 5000].filter(m => m / s < w * 0.35).pop() ?? 100
  ctx.strokeStyle = '#fff'; ctx.lineWidth = 2
  ctx.beginPath(); ctx.moveTo(10, h - 12); ctx.lineTo(10 + bar / s, h - 12); ctx.stroke()
  ctx.fillStyle = '#fff'; ctx.font = '600 11px system-ui'; ctx.textAlign = 'center'
  ctx.fillText(bar >= 1000 ? `${bar / 1000} km` : `${bar} m`, 10 + bar / s / 2, h - 20)
  ctx.fillText('N ↑', 18, 16)
}

function plane(ctx: CanvasRenderingContext2D, x: number, y: number, heading: number, color: string) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rad(heading))
  ctx.beginPath(); ctx.moveTo(0, -9); ctx.lineTo(6, 7); ctx.lineTo(0, 4); ctx.lineTo(-6, 7); ctx.closePath()
  ctx.fillStyle = color; ctx.fill(); ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 1; ctx.stroke()
  ctx.restore()
}

export function drawProfile(canvas: HTMLCanvasElement, f: Frame, showGlidepath: boolean) {
  const { ctx, w, h } = prepCanvas(canvas)
  const t = f.telemetry, me = t.position
  const track = t.groundSpeedKt > 5 ? t.trackDeg : t.headingDeg
  const dir = new Vec3(Math.sin(rad(track)), 0, -Math.cos(rad(track)))
  const behind = 1500, ahead = 6000
  const samples: [number, number][] = []
  for (let d = -behind; d <= ahead; d += 60) { const p = me.add(dir.mul(d)); samples.push([d, Terrain.height(p.x, p.z)]) }
  const maxT = Math.max(...samples.map(s => s[1])), minT = Math.min(...samples.map(s => s[1]))
  const top = Math.max(me.y, maxT) + Math.max(200, Math.max(me.y, maxT) * 0.35)
  const bottom = Math.max(0, Math.min(me.y, minT) - 60)
  const pt = (d: number, alt: number) => [((d + behind) / (ahead + behind)) * w, h - ((alt - bottom) / (top - bottom)) * h] as const

  ctx.fillStyle = '#9ec7ed'; ctx.fillRect(0, 0, w, h)
  ctx.fillStyle = '#617f4d'
  ctx.beginPath(); ctx.moveTo(0, h); for (const [d, hh] of samples) ctx.lineTo(...pt(d, hh)); ctx.lineTo(w, h); ctx.closePath(); ctx.fill()

  ctx.font = '600 11px system-ui'
  if (showGlidepath && Math.abs(headingDelta(track, 0)) < 45 && me.z > Terrain.runwayNorthEnd && me.z < Terrain.runwaySouthEnd + 8000 && Math.abs(me.x) < 2000) {
    const touchdownZ = Terrain.runwaySouthEnd - 300
    ctx.strokeStyle = 'rgba(175,82,222,0.85)'; ctx.lineWidth = 1.5; ctx.setLineDash([6, 4])
    ctx.beginPath()
    for (let d = -behind; d <= ahead; d += 100) { const alt = Math.max(0, (me.z - d - touchdownZ) * Math.tan(rad(3))); d === -behind ? ctx.moveTo(...pt(d, alt)) : ctx.lineTo(...pt(d, alt)) }
    ctx.stroke(); ctx.setLineDash([])
    ctx.fillStyle = '#af52de'; ctx.textAlign = 'right'; ctx.fillText('3° glidepath', w - 8, 12)
  }

  const hist = f.trail.slice(-60).filter(p => p.sub(me).dot(dir) > -behind)
  if (hist.length) {
    ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 1.5; ctx.setLineDash([4, 3])
    ctx.beginPath(); hist.forEach((p, i) => { const q = pt(p.sub(me).dot(dir), p.y); i ? ctx.lineTo(...q) : ctx.moveTo(...q) }); ctx.lineTo(...pt(0, me.y)); ctx.stroke(); ctx.setLineDash([])
  }

  const [px, py] = pt(0, me.y)
  ctx.save(); ctx.translate(px, py); ctx.rotate(rad(-t.pitchDeg))
  ctx.beginPath(); ctx.moveTo(10, 0); ctx.lineTo(-8, -2); ctx.lineTo(-10, -7); ctx.lineTo(-12, -7); ctx.lineTo(-11, 2); ctx.closePath()
  ctx.fillStyle = '#ffd60a'; ctx.fill(); ctx.strokeStyle = '#000'; ctx.lineWidth = 0.8; ctx.stroke()
  ctx.restore()

  ctx.fillStyle = '#000'; ctx.textAlign = 'left'; ctx.fillText(`AGL ${fmt.altitude(t.aglFt)}`, 8, 12)
  ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.textAlign = 'center'; ctx.fillText('← 1.5 km   ahead 6 km →', w / 2, h - 6)
}
