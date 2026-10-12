// Port of FlightCore/Lessons.swift.
import { Units, Vec3, rad, deg, wrap360, headingDelta } from './math'
import { Terrain } from './environment'
import type { AircraftKind, TouchdownReport } from './aircraft'
import { emptyTelemetry, type Telemetry } from './telemetry'

export type LessonCategory = 'Basics' | 'Maneuvers' | 'Takeoff' | 'Landing' | 'Low Level' | 'Dogfight'
export const categoryGroup = (c: LessonCategory) =>
  c === 'Basics' || c === 'Maneuvers' ? 'Airwork' : c === 'Takeoff' || c === 'Landing' ? 'Takeoff & Landing' : 'Top Gun'

export interface StepContext {
  start: Telemetry; elapsed: number; gatesPassed: number; gatesMissed: number; gatesTotal: number
  banditDistance: number | null; banditDestroyed: boolean; lastTouchdown: TouchdownReport | null
}

type Check = (t: Telemetry, c: StepContext) => boolean
export interface LessonStep {
  title: string; instruction: string; tip: string; hold: number; check: Check
  fail?: (t: Telemetry, c: StepContext) => string | null
  progress?: (t: Telemetry, c: StepContext) => string
}

export type LessonStart =
  | { kind: 'runway' }
  | { kind: 'air'; x: number; altitudeFt: number; z: number; headingDeg: number; speedKt: number; flaps: number; gearDown: boolean | null }

export interface Lesson {
  id: string; number: number; title: string; category: LessonCategory; aircraft: AircraftKind
  summary: string; objectives: string[]; start: LessonStart; hasGates?: boolean; hasBandit?: boolean; steps: LessonStep[]
}

export type LessonStatus = { kind: 'running' } | { kind: 'passed' } | { kind: 'failed'; reason: string }

export class LessonProgress {
  stepIndex = 0
  status: LessonStatus = { kind: 'running' }
  holdTime = 0
  private stepStart: Telemetry = emptyTelemetry()
  private stepStartTime = 0
  private started = false

  constructor(public lesson: Lesson) {}

  get currentStep(): LessonStep | undefined { return this.lesson.steps[this.stepIndex] }

  context(t: Telemetry, mission: StepContext): StepContext {
    return { ...mission, start: this.stepStart, elapsed: t.time - this.stepStartTime }
  }

  /** Returns true when a step was just completed. */
  update(t: Telemetry, mission: StepContext, dt: number): boolean {
    const step = this.currentStep
    if (this.status.kind !== 'running' || !step) return false
    if (!this.started) { this.started = true; this.stepStart = t; this.stepStartTime = t.time }
    if (t.crashed) { this.status = { kind: 'failed', reason: t.crashReason ?? 'Crashed' }; return false }
    const ctx = this.context(t, mission)
    const reason = step.fail?.(t, ctx)
    if (reason) { this.status = { kind: 'failed', reason }; return false }
    if (!step.check(t, ctx)) { this.holdTime = 0; return false }
    this.holdTime += dt
    if (this.holdTime < step.hold) return false
    this.stepIndex += 1
    this.holdTime = 0
    this.stepStart = t
    this.stepStartTime = t.time
    if (this.stepIndex >= this.lesson.steps.length) this.status = { kind: 'passed' }
    return true
  }
}

// MARK: - Canyon route

export interface Gate { id: number; center: Vec3; normal: Vec3; radius: number; status: 'pending' | 'passed' | 'missed' }

export const CanyonRoute = {
  firstZ: -7000,
  gateSpacing: 900,
  gateCount: 12,
  tangent(z: number) { return new Vec3(-Math.cos(z / 1800), 0, -1).normalized() },
  gates(): Gate[] {
    return Array.from({ length: this.gateCount }, (_, i) => {
      const z = this.firstZ - i * this.gateSpacing
      const x = Terrain.canyonCenterX(z)
      return { id: i, center: new Vec3(x, Terrain.height(x, z) + 70, z), normal: this.tangent(z), radius: 40, status: 'pending' as const }
    })
  },
  get start(): LessonStart {
    const z = -4200
    const t = this.tangent(z)
    const x = Terrain.canyonCenterX(z)
    return { kind: 'air', x, altitudeFt: (Terrain.height(x, z) + 260) / Units.foot, z, headingDeg: wrap360(deg(Math.atan2(t.x, -t.z))), speedKt: 360, flaps: 0, gearDown: false }
  },
}

// MARK: - Catalog

const ft = (v: number) => Math.round(v).toLocaleString('en-US')
const within = (a: number, b: number, tol: number) => Math.abs(a - b) <= tol
const i = Math.trunc
const signed = (v: number) => (v >= 0 ? '+' : '') + v.toFixed(0)
const step = (title: string, instruction: string, o: Partial<LessonStep> & { check: Check }): LessonStep =>
  ({ title, instruction, tip: '', hold: 0, ...o })

const cruise: LessonStart = { kind: 'air', x: 0, altitudeFt: 3000, z: 2000, headingDeg: 0, speedKt: 105, flaps: 0, gearDown: null }
const fighterStart: LessonStart = { kind: 'air', x: 0, altitudeFt: 12000, z: 0, headingDeg: 0, speedKt: 380, flaps: 0, gearDown: false }
const offRunway = (t: Telemetry) => (t.onGround && !t.onRunway && t.groundSpeedKt > 5 ? 'Ran off the runway' : null)
const turnFail = (t: Telemetry, c: StepContext) => (Math.abs(t.altitudeFt - c.start.altitudeFt) > 500 ? 'Lost or gained more than 500 ft in the turn' : null)

export const LESSONS: Lesson[] = [
  {
    id: 'controls', number: 1, title: 'The Controls', category: 'Basics', aircraft: 'trainer',
    summary: 'Meet the three axes: pitch, roll and yaw, and the throttle.',
    objectives: ['Pitch with the elevator', 'Bank with the ailerons', 'Yaw with the rudder', 'Use the throttle'],
    start: cruise,
    steps: [
      step('Pitch up', 'Pull back gently (S or ↓) until the nose is 10° above the horizon.', { tip: 'The elevator on the tail pushes the tail down, which tips the nose up.', hold: 1, check: t => t.pitchDeg > 8, progress: t => `Pitch ${i(t.pitchDeg)}° (target 10° up)` }),
      step('Pitch down', 'Push forward (W or ↑) until the nose is below the horizon.', { tip: 'Watch the airspeed rise as the nose drops. Pitch trades height for speed.', hold: 1, check: t => t.pitchDeg < -3, progress: t => `Pitch ${i(t.pitchDeg)}° (target below 0°)` }),
      step('Level the nose', 'Bring the nose back to the horizon and hold it there.', { hold: 2, check: t => Math.abs(t.pitchDeg) < 3 }),
      step('Roll left', 'Push the stick left (A or ←) to bank 30° left.', { tip: 'The ailerons move in opposite directions: one wing gains lift, the other loses it.', hold: 1, check: t => t.bankDeg < -25, progress: t => `Bank ${i(t.bankDeg)}°` }),
      step('Roll right', 'Now roll the other way to 30° right (D or →).', { hold: 1, check: t => t.bankDeg > 25, progress: t => `Bank ${i(t.bankDeg)}°` }),
      step('Wings level', 'Centre the stick and level the wings.', { hold: 2, check: t => Math.abs(t.bankDeg) < 5 && Math.abs(t.pitchDeg) < 6 }),
      step('Yaw', 'Press the rudder (Q or E) and watch the nose slide sideways. Turn auto-rudder off in Settings to feel it fully.', { tip: "Rudder points the nose. It doesn't turn the plane by itself; banking does.", hold: 0.5, check: t => Math.abs(t.rudder) > 0.5 }),
      step('Power back', 'Pull the throttle to idle (F). Notice the nose wants to drop.', { check: t => t.throttle < 0.1 }),
      step('Full power', 'Push the throttle full forward (R).', { check: t => t.throttle > 0.95 }),
    ],
  },
  {
    id: 'straight-level', number: 2, title: 'Straight and Level', category: 'Basics', aircraft: 'trainer',
    summary: 'Hold a constant altitude and heading, and use trim to fly hands-off.',
    objectives: ['Hold altitude ±100 ft', 'Hold heading ±10°', 'Trim off the control pressure'],
    start: { kind: 'air', x: 0, altitudeFt: 3000, z: 2000, headingDeg: 0, speedKt: 95, flaps: 0, gearDown: null },
    steps: [
      step('Hold it steady', 'Keep altitude within 100 ft and heading within 10° of where you started, for 20 seconds.', {
        tip: 'Pick a spot on the horizon and keep the nose on it. Small corrections, early.', hold: 20,
        check: (t, c) => within(t.altitudeFt, c.start.altitudeFt, 100) && Math.abs(headingDelta(t.headingDeg, c.start.headingDeg)) < 10,
        fail: (t, c) => (Math.abs(t.altitudeFt - c.start.altitudeFt) > 600 ? 'Drifted more than 600 ft off altitude' : null),
        progress: (t, c) => `Alt ${ft(t.altitudeFt)} ft (target ${ft(c.start.altitudeFt)})   Hdg ${i(t.headingDeg)}°` }),
      step('Trim for hands-off', 'Let go of the stick, then use trim (, nose down / . nose up) until the vertical speed stays near zero for 6 seconds.', {
        tip: 'Trim tells the aeroplane what attitude to hold. A trimmed plane flies itself.', hold: 6,
        check: t => Math.abs(t.stickPitch) < 0.05 && Math.abs(t.verticalSpeedFpm) < 200,
        progress: t => `VS ${i(t.verticalSpeedFpm)} fpm, trim ${t.trim >= 0 ? '+' : ''}${t.trim.toFixed(2)}` }),
    ],
  },
  {
    id: 'power-pitch', number: 3, title: 'Power and Pitch', category: 'Basics', aircraft: 'trainer',
    summary: 'Change airspeed without changing altitude: power and pitch work together.',
    objectives: ['Slow down while holding altitude', 'Speed up while holding altitude'],
    start: cruise,
    steps: [
      step('Slow to 75 kt', 'Reduce power (F) and raise the nose gradually to hold altitude as you slow to 70–80 kt.', {
        tip: 'Less speed means less lift, so you need more angle of attack (nose up) to stay level.', hold: 5,
        check: (t, c) => within(t.airspeedKt, 75, 5) && within(t.altitudeFt, c.start.altitudeFt, 150),
        progress: (t, c) => `Speed ${i(t.airspeedKt)} kt   Alt ${ft(t.altitudeFt - c.start.altitudeFt)} ft from start` }),
      step('Speed up to 110 kt', 'Add power (R) and lower the nose to stay level as you accelerate to 105–115 kt.', {
        hold: 5, check: (t, c) => within(t.airspeedKt, 110, 5) && within(t.altitudeFt, c.start.altitudeFt, 150),
        progress: (t, c) => `Speed ${i(t.airspeedKt)} kt   Alt ${ft(t.altitudeFt - c.start.altitudeFt)} ft from start` }),
    ],
  },
  {
    id: 'turns', number: 4, title: 'Turns', category: 'Maneuvers', aircraft: 'trainer',
    summary: 'Bank to turn, add back pressure to hold altitude, roll out on a heading.',
    objectives: ['30° banked turns', 'Hold altitude in the turn', 'Roll out on a target heading'],
    start: cruise,
    steps: [
      step('Bank left 30°', 'Roll into a 30° left bank and hold it.', { tip: 'Banking tilts the lift sideways. That sideways pull is what turns you.', hold: 3, check: t => within(t.bankDeg, -30, 7), progress: t => `Bank ${i(t.bankDeg)}°` }),
      step('Turn to 270°', 'Keep the bank, add a little back pressure to hold altitude, and roll wings level on heading 270° (west).', {
        tip: 'Start rolling out about 10° before the target heading.', hold: 2,
        check: t => Math.abs(headingDelta(t.headingDeg, 270)) < 10 && Math.abs(t.bankDeg) < 6, fail: turnFail,
        progress: (t, c) => `Hdg ${i(t.headingDeg)}° → 270°   Alt Δ ${ft(t.altitudeFt - c.start.altitudeFt)} ft` }),
      step('Turn right to 360°', 'Now a 30° right turn back to north (360°), rolling out wings level.', {
        hold: 2, check: t => Math.abs(headingDelta(t.headingDeg, 0)) < 10 && Math.abs(t.bankDeg) < 6, fail: turnFail,
        progress: t => `Hdg ${i(t.headingDeg)}° → 360°   Bank ${i(t.bankDeg)}°` }),
    ],
  },
  {
    id: 'climbs-descents', number: 5, title: 'Climbs and Descents', category: 'Maneuvers', aircraft: 'trainer',
    summary: 'Climb and descend at a set speed, and level off on a target altitude.',
    objectives: ['Climb 500 ft at 75 kt', 'Level off', 'Descend at about 500 fpm'],
    start: cruise,
    steps: [
      step('Climb 500 ft', 'Full power (R) and raise the nose to hold about 75 kt. Climb to 3,500 ft.', {
        tip: 'In a climb, pitch sets your airspeed and power sets your climb rate.',
        check: t => t.altitudeFt >= 3480, progress: t => `Alt ${ft(t.altitudeFt)} / 3,500 ft   Speed ${i(t.airspeedKt)} kt` }),
      step('Level off at 3,500', 'Lower the nose to the horizon, let speed build, then reduce power. Hold 3,500 ft.', {
        tip: 'Attitude, then power, then trim: APT.', hold: 5,
        check: t => within(t.altitudeFt, 3500, 100) && Math.abs(t.verticalSpeedFpm) < 250,
        progress: t => `Alt ${ft(t.altitudeFt)} ft   VS ${i(t.verticalSpeedFpm)} fpm` }),
      step('Descend to 3,000', 'Reduce power a little and lower the nose for about 500 fpm down. Level at 3,000 ft.', {
        hold: 4, check: t => within(t.altitudeFt, 3000, 100) && Math.abs(t.verticalSpeedFpm) < 250,
        progress: t => `Alt ${ft(t.altitudeFt)} → 3,000 ft   VS ${i(t.verticalSpeedFpm)} fpm` }),
    ],
  },
  {
    id: 'stalls', number: 6, title: 'Slow Flight and Stalls', category: 'Maneuvers', aircraft: 'trainer',
    summary: 'Feel the stall coming, let it happen, and recover the right way.',
    objectives: ['Recognise the stall warning', 'Stall the wing', 'Recover: nose down, full power, wings level'],
    start: { kind: 'air', x: 0, altitudeFt: 4500, z: 2000, headingDeg: 0, speedKt: 95, flaps: 0, gearDown: null },
    steps: [
      step('Power to idle', 'Pull the throttle to idle (F) and keep the nose level as you slow down.', { check: t => t.throttle < 0.15 }),
      step('Stall it', 'Keep raising the nose to hold altitude until the wing stalls. Watch the AoA climb.', {
        tip: 'The stall happens at a critical angle of attack (~15° here), not a particular speed.',
        check: t => t.stalled, progress: t => `AoA ${i(t.alphaDeg)}° (stalls ≈ 15°)   Speed ${i(t.airspeedKt)} kt` }),
      step('Recover', 'Stick FORWARD to un-stall the wing, full power (R), wings level with ailerons and rudder.', {
        tip: 'Every stall recovery starts with reducing angle of attack.', hold: 2,
        check: t => !t.stalled && t.throttle > 0.9 && t.alphaDeg < 10,
        fail: t => (t.aglFt < 800 ? 'Too low: recover with more altitude next time' : null) }),
      step('Climb away', 'Once flying again, gently pull out of the dive and climb at 70+ kt.', {
        hold: 3, check: t => t.verticalSpeedFpm > 0 && t.airspeedKt > 65 && !t.stalled,
        fail: t => (t.aglFt < 500 ? 'Too low: recover with more altitude next time' : null) }),
    ],
  },
  {
    id: 'takeoff', number: 7, title: 'Takeoff', category: 'Takeoff', aircraft: 'trainer',
    summary: 'Full power, keep it straight, rotate and climb out.',
    objectives: ['Track the centreline with rudder', 'Rotate at 55 kt', 'Climb at 75 kt to 500 ft'],
    start: { kind: 'runway' },
    steps: [
      step('Full power', 'Release the brakes and push the throttle to full (hold R).', { check: t => t.throttle > 0.95 }),
      step('Keep it straight', 'The propeller pulls you left: use rudder (E / Q) to stay on the centreline as you accelerate. Auto-rudder helps; switch it off in Settings to feel it.', {
        tip: 'Look far down the runway, not at the nose.', check: t => t.airspeedKt > 45, fail: offRunway,
        progress: t => `Speed ${i(t.airspeedKt)} kt   Centreline ${signed(t.position.x)} m` }),
      step('Rotate', 'At 55 kt ease back (S / ↓) to raise the nose about 8° and fly off.', { check: t => !t.onGround && t.aglFt > 20, fail: offRunway }),
      step('Climb out', 'Climb at about 75 kt to 500 ft above the ground.', {
        tip: 'Hold the nose about 8–10° up and watch the airspeed.', check: t => t.aglFt > 500,
        progress: t => `AGL ${ft(t.aglFt)} / 500 ft   Speed ${i(t.airspeedKt)} kt` }),
    ],
  },
  {
    id: 'landing', number: 8, title: 'Landing', category: 'Landing', aircraft: 'trainer',
    summary: 'Fly a stabilised approach from 2 miles out, flare, touch down and stop.',
    objectives: ['Configure flaps', 'Hold 65 kt on a ~3° glidepath', 'Flare and touch down gently', 'Stop on the runway'],
    start: { kind: 'air', x: 0, altitudeFt: 650, z: Terrain.runwaySouthEnd + 3700, headingDeg: 0, speedKt: 75, flaps: 1 / 3, gearDown: null },
    steps: [
      step('Configure', 'Set full flaps (] twice more) and slow to 60–70 kt.', {
        tip: 'Flaps add lift and drag, so you can fly slower and descend steeper.', hold: 2,
        check: t => t.flapsDeg >= 25 && within(t.airspeedKt, 65, 6), progress: t => `Flaps ${i(t.flapsDeg)}°   Speed ${i(t.airspeedKt)} kt` }),
      step('Fly the glidepath', 'Aim at the runway numbers. Keep about 65 kt and 400–500 fpm down. Power controls the descent.', {
        tip: "If the numbers move up the windshield you're going to land short: add power.",
        check: t => t.aglFt < 30 && !t.onGround,
        progress: t => {
          const dist = Math.max(t.position.z - Terrain.runwaySouthEnd, 1)
          return `AGL ${ft(t.aglFt)} ft (glidepath ${ft((dist * Math.tan(rad(3))) / Units.foot)})   Speed ${i(t.airspeedKt)} kt`
        } }),
      step('Flare', 'Power to idle and gently raise the nose to slow the descent just above the runway.', {
        tip: 'Hold it off. Let the plane settle onto the main wheels.', check: t => t.onGround,
        fail: t => (t.onGround && !t.onRunway ? 'Touched down off the runway' : null) }),
      step('Stop', 'Hold the brakes (B) and keep straight with rudder until stopped.', { check: t => t.groundSpeedKt < 3 && t.onGround, fail: offRunway }),
    ],
  },
  {
    id: 'jet-fam', number: 9, title: 'Jet Familiarization', category: 'Dogfight', aircraft: 'fighter',
    summary: 'Get a feel for the fighter: afterburner, high-g turns and the vertical.',
    objectives: ['Light the afterburner', 'Sustain a 5 g turn', 'Go vertical', 'Recover to level flight'],
    start: fighterStart,
    steps: [
      step('Afterburner', 'Push the throttle all the way (hold R) to light the burners.', { check: t => t.afterburner }),
      step('Pull 5 g', 'Bank 70–80° and pull hard to hold 5 g or more for 3 seconds.', {
        tip: 'The fly-by-wire system limits you to 7.5 g. Feel how fast the speed bleeds.', hold: 3,
        check: t => t.gLoad > 5, progress: t => `${t.gLoad.toFixed(1)} g` }),
      step('Go vertical', 'Roll wings level and pull to 60° nose-up or more.', { check: t => t.pitchDeg > 60, progress: t => `Pitch ${i(t.pitchDeg)}°` }),
      step('Recover', 'Roll and pull back to level flight: pitch within 5°, wings within 10°.', {
        hold: 3, check: t => Math.abs(t.pitchDeg) < 5 && Math.abs(t.bankDeg) < 10, fail: t => (t.aglFt < 1500 ? 'Too low' : null) }),
    ],
  },
  {
    id: 'canyon-run', number: 10, title: 'Canyon Run', category: 'Low Level', aircraft: 'fighter',
    summary: 'Thread the gates down a winding canyon, low and fast.',
    objectives: ['Fly every gate', 'Stay below the canyon rim', "Don't hit the walls"],
    start: CanyonRoute.start, hasGates: true,
    steps: [
      step('Fly the gates', 'Fly through every orange ring. Use the map to see the next turn coming.', {
        tip: 'Look through the turn. Bank first, then pull.',
        check: (_, c) => c.gatesPassed + c.gatesMissed >= c.gatesTotal && c.gatesTotal > 0,
        progress: (_, c) => `Gates ${c.gatesPassed}/${c.gatesTotal}` + (c.gatesMissed > 0 ? `   missed ${c.gatesMissed}` : '') }),
    ],
  },
  {
    id: 'dogfight', number: 11, title: 'Dogfight', category: 'Dogfight', aircraft: 'fighter',
    summary: 'One bandit, guns only. Get behind it and shoot it down.',
    objectives: ['Find the bandit', 'Turn to get behind it', 'Guns kill (Space)'],
    start: fighterStart, hasBandit: true,
    steps: [
      step('Merge', 'The bandit is ahead (red box on the HUD). Fly toward it.', {
        tip: "Watch the arrow at the edge of the HUD when it's off-screen.",
        check: (_, c) => (c.banditDistance ?? 1e9) < 2000, progress: (_, c) => `Range ${((c.banditDistance ?? 0) / 1852).toFixed(1)} nm` }),
      step('Guns kill', 'Turn behind it, put the pipper on it and hold Space to fire.', {
        tip: 'Turn into the bandit to cut across its circle; then match its turn.',
        check: (_, c) => c.banditDestroyed, fail: t => (t.health <= 0 ? 'You were shot down' : null),
        progress: (_, c) => `Range ${i(c.banditDistance ?? 0)} m` }),
    ],
  },
]

export const lessonById = (id: string) => LESSONS.find(l => l.id === id)
