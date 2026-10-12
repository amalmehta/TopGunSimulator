// What the panels draw each frame (mirrors FrameSnapshot in the Mac app).
import type { Vec3 } from '../core/math'
import type { Telemetry } from '../core/telemetry'
import type { Hint } from '../core/instructor'
import type { Gate, LessonStatus } from '../core/lessons'
import type { TouchdownReport } from '../core/aircraft'

export interface Frame {
  telemetry: Telemetry
  hints: Hint[]
  lessonStatus: LessonStatus | null
  lessonStepIndex: number
  lessonProgressText: string | null
  lessonHold: number
  gates: Gate[]
  trail: Vec3[]
  banditTrail: Vec3[]
  banditPosition: Vec3 | null
  banditHeading: number
  banditHealth: number
  banditDistance: number | null
  banditScreen: { x: number; y: number } | null
  nextGateScreen: { x: number; y: number } | null
  ammo: number
  touchdown: TouchdownReport | null
}

/** Sizes a canvas for its CSS box at device pixel ratio and returns a context in CSS pixels. */
export function prepCanvas(canvas: HTMLCanvasElement) {
  const dpr = window.devicePixelRatio || 1
  const w = canvas.clientWidth, h = canvas.clientHeight
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr)
    canvas.height = Math.round(h * dpr)
  }
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, w, h)
  return { ctx, w, h }
}
