// Port of FlightCore/Session.swift: one flight with lesson, instructor, gates, bandit and guns.
import { Vec3, Units, clamp, rad } from './math'
import { Terrain, WindModel } from './environment'
import { Aircraft, PilotInput, specOf, type AircraftKind, type TouchdownReport } from './aircraft'
import { makeTelemetry, type Telemetry } from './telemetry'
import { Instructor, type Hint } from './instructor'
import { CanyonRoute, LessonProgress, type Gate, type Lesson, type StepContext, type LessonStatus } from './lessons'

/** Flies the bandit with the same physics as the player. */
export class BanditAI {
  constructor(public skill = 0.7) {}

  input(bandit: Aircraft, target: Aircraft): PilotInput {
    const input = new PilotInput()
    const me = bandit.state
    const toTarget = target.state.position.sub(me.position)
    const distance = toTarget.length()
    const leadTime = clamp(distance / 900, 0, 1.2) * this.skill
    let aim = target.state.position.add(target.state.velocity.mul(leadTime)).sub(me.position)

    const ahead = me.position.add(me.velocity.mul(5))
    const clearance = ahead.y - Terrain.height(ahead.x, ahead.z)
    const agl = me.position.y - Terrain.height(me.position.x, me.position.z)
    if (clearance < 600 || agl < 500) aim = new Vec3(me.velocity.x, me.velocity.length() * 1.5, me.velocity.z)

    const d = me.orientation.inverse().act(aim).normalized()
    const bankError = Math.atan2(d.x, d.y)
    const offNose = Math.acos(clamp(-d.z, -1, 1))
    const rollGain = 1.5 * (0.5 + this.skill)
    input.roll = clamp(bankError * rollGain - me.rollRate * 0.15, -1, 1) * (offNose < 0.03 ? 0.2 : 1)
    input.pitch = clamp(Math.atan2(d.y, -d.z) * 2.5, -0.3, 1) * (0.6 + 0.4 * this.skill)
    input.throttle = distance > 1200 ? 1.0 : 0.9
    input.trigger = offNose < rad(2.5) && distance < 900
    return input
  }
}

export type SessionEvent =
  | { kind: 'stepCompleted'; title: string } | { kind: 'lessonPassed' } | { kind: 'lessonFailed'; reason: string }
  | { kind: 'crashed'; reason: string } | { kind: 'touchdown'; report: TouchdownReport }
  | { kind: 'gatePassed'; index: number } | { kind: 'gateMissed'; index: number }
  | { kind: 'hitBandit' } | { kind: 'gotHit' } | { kind: 'banditDestroyed' }

export type SessionMode = { kind: 'free'; aircraft: AircraftKind; airborne: boolean } | { kind: 'lesson'; lesson: Lesson }

export const modeTitle = (m: SessionMode) =>
  m.kind === 'free' ? `Free Flight — ${specOf(m.aircraft).name}` : `Lesson ${m.lesson.number}: ${m.lesson.title}`

export function onTarget(shooter: { position: Vec3; forward: Vec3 }, target: { position: Vec3 }, cone: number, range: number) {
  const to = target.position.sub(shooter.position)
  const d = to.length()
  if (!(d < range && d > 1)) return false
  const angle = Math.acos(clamp(to.mul(1 / d).dot(shooter.forward), -1, 1))
  return angle < cone + Math.atan(6 / d)
}

export class FlightSession {
  static readonly physicsRate = 240
  player: Aircraft
  bandit: Aircraft | null = null
  banditAI = new BanditAI()
  gates: Gate[] = []
  input = new PilotInput()
  time = 0
  lesson: LessonProgress | null = null
  instructor = new Instructor()
  hints: Hint[] = []
  telemetry: Telemetry
  events: SessionEvent[] = []
  ammo = 600
  firing = false
  banditFiring = false
  trail: Vec3[] = []
  banditTrail: Vec3[] = []
  paused = false
  private accumulator = 0
  private wasCrashed = false
  private lastTouchdownCount = 0
  private trailTimer = 0

  constructor(public mode: SessionMode, autoRudder = true, public wind = new WindModel()) {
    if (mode.kind === 'free') {
      this.player = new Aircraft(specOf(mode.aircraft))
      if (mode.airborne) {
        const trainer = mode.aircraft === 'trainer'
        this.player.placeInFlight(new Vec3(0, (trainer ? 3000 : 10000) * Units.foot, 3000), 0, trainer ? this.player.spec.vCruiseKt * 0.9 : 380)
      } else this.player.placeOnRunway()
    } else {
      const l = mode.lesson
      this.player = new Aircraft(specOf(l.aircraft))
      if (l.start.kind === 'runway') this.player.placeOnRunway()
      else this.player.placeInFlight(new Vec3(l.start.x, l.start.altitudeFt * Units.foot, l.start.z), l.start.headingDeg, l.start.speedKt, l.start.gearDown, l.start.flaps)
      this.lesson = new LessonProgress(l)
      if (l.hasGates) this.gates = CanyonRoute.gates()
      if (l.hasBandit) {
        const b = new Aircraft(specOf('fighter'))
        b.placeInFlight(this.player.state.position.add(new Vec3(600, 150, -6000)), 180, 380, false)
        this.bandit = b
      }
    }
    this.player.autoRudder = autoRudder
    this.input.throttle = this.player.state.engine
    this.telemetry = makeTelemetry(this.player, this.input, 0)
  }

  get outcome(): LessonStatus | null { return this.lesson?.status ?? null }
  get banditDistance() { return this.bandit ? this.bandit.state.position.sub(this.player.state.position).length() : null }

  drainEvents() { const e = this.events; this.events = []; return e }

  advance(frameTime: number) {
    if (this.paused) return
    this.accumulator += Math.min(frameTime, 0.1)
    const dt = 1 / FlightSession.physicsRate
    let steps = 0
    // Small epsilon so frame times like 1/60 always yield exactly 4 steps despite float rounding.
    while (this.accumulator >= dt - 1e-9) { this.step(dt); this.accumulator -= dt; steps++ }
    const frameDt = steps * dt
    if (frameDt <= 0) return
    this.telemetry = makeTelemetry(this.player, this.input, this.time)
    this.hints = this.instructor.evaluate(this.telemetry, this.player.spec, frameDt)
    this.updateLesson(frameDt)
    this.recordTrails(frameDt)
  }

  step(dt: number) {
    this.time += dt
    const p = this.player.state.position
    const w = this.wind.sample(dt, p.y - Terrain.height(p.x, p.z))
    const before = p.clone()
    this.player.step(dt, this.input, w)
    if (this.player.state.crashed && !this.wasCrashed) {
      this.wasCrashed = true
      this.events.push({ kind: 'crashed', reason: this.player.state.crashReason ?? 'Crashed' })
    }
    if (this.player.touchdownCount !== this.lastTouchdownCount && this.player.lastTouchdown) {
      this.lastTouchdownCount = this.player.touchdownCount
      this.events.push({ kind: 'touchdown', report: this.player.lastTouchdown })
    }
    this.updateGates(before, this.player.state.position)
    this.updateCombat(dt)
  }

  updateGates(a: Vec3, b: Vec3) {
    for (const g of this.gates) {
      if (g.status !== 'pending') continue
      const da = a.sub(g.center).dot(g.normal), db = b.sub(g.center).dot(g.normal)
      if (!(da < 0 && db >= 0)) continue
      const crossing = a.add(b.sub(a).mul(da / (da - db)))
      if (crossing.sub(g.center).length() <= g.radius) { g.status = 'passed'; this.events.push({ kind: 'gatePassed', index: g.id }) }
      else { g.status = 'missed'; this.events.push({ kind: 'gateMissed', index: g.id }) }
    }
  }

  private updateCombat(dt: number) {
    const b = this.bandit
    if (!b) return
    const ps = this.player.state
    this.firing = this.input.trigger && this.ammo > 0 && !ps.crashed
    if (this.firing) {
      this.ammo = Math.max(0, this.ammo - Math.ceil(100 * dt))
      if (b.state.health > 0 && onTarget(ps, b.state, rad(1.2), 1200)) {
        b.state.health -= 40 * dt
        if (Math.trunc(this.time * 10) !== Math.trunc((this.time - dt) * 10)) this.events.push({ kind: 'hitBandit' })
        if (b.state.health <= 0) { b.state.health = 0; this.events.push({ kind: 'banditDestroyed' }) }
      }
    }
    if (b.state.health > 0 && !b.state.crashed) {
      const ai = this.banditAI.input(b, this.player)
      if (ps.crashed) ai.trigger = false
      this.banditFiring = ai.trigger
      b.step(dt, ai, this.wind.steady)
      if (ai.trigger && onTarget(b.state, ps, rad(2), 900)) {
        ps.health -= 12 * dt * this.banditAI.skill
        if (Math.trunc(this.time * 4) !== Math.trunc((this.time - dt) * 4)) this.events.push({ kind: 'gotHit' })
        if (ps.health <= 0) { ps.health = 0; ps.crashed = true; ps.crashReason = 'Shot down by the bandit' }
      }
      if (b.state.crashed && b.state.health > 0) { b.state.health = 0; this.events.push({ kind: 'banditDestroyed' }) }
    } else {
      this.banditFiring = false
      b.state.velocity = b.state.velocity.add(new Vec3(0, -Units.g * dt, 0))
      b.state.position = b.state.position.add(b.state.velocity.mul(dt))
    }
  }

  private missionContext(): StepContext {
    return {
      start: this.telemetry, elapsed: 0,
      gatesPassed: this.gates.filter(g => g.status === 'passed').length,
      gatesMissed: this.gates.filter(g => g.status === 'missed').length,
      gatesTotal: this.gates.length,
      banditDistance: this.banditDistance,
      banditDestroyed: this.bandit ? this.bandit.state.health <= 0 : false,
      lastTouchdown: this.player.lastTouchdown,
    }
  }

  private updateLesson(dt: number) {
    const progress = this.lesson
    if (!progress || progress.status.kind !== 'running') return
    const title = progress.currentStep?.title ?? ''
    if (progress.update(this.telemetry, this.missionContext(), dt)) this.events.push({ kind: 'stepCompleted', title })
    const st = progress.status as LessonStatus
    if (st.kind === 'passed') this.events.push({ kind: 'lessonPassed' })
    else if (st.kind === 'failed') this.events.push({ kind: 'lessonFailed', reason: st.reason })
  }

  /** Context for the lesson panel's live progress text. */
  get stepContext(): StepContext | null {
    return this.lesson ? this.lesson.context(this.telemetry, this.missionContext()) : null
  }

  private recordTrails(dt: number) {
    this.trailTimer += dt
    if (this.trailTimer < 0.5) return
    this.trailTimer = 0
    this.trail.push(this.player.state.position.clone())
    if (this.trail.length > 1200) this.trail.splice(0, this.trail.length - 1200)
    if (this.bandit) {
      this.banditTrail.push(this.bandit.state.position.clone())
      if (this.banditTrail.length > 240) this.banditTrail.shift()
    }
  }

  setFlaps(step: number) { this.player.setFlaps(step) }
  toggleGear() { this.player.toggleGear() }
  adjustTrim(d: number) { this.player.adjustTrim(d) }
}
