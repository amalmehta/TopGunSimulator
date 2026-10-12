// Top Gun Simulator (web): frame loop, screens, panels and dialogs.
import * as THREE from 'three'
import './style.css'
import { specOf, type AircraftKind } from './core/aircraft'
import { FlightSession, modeTitle, type SessionMode, type SessionEvent } from './core/session'
import { LESSONS, categoryGroup, lessonById, type Lesson, type LessonCategory } from './core/lessons'
import { World, CAMERA_MODES, type CameraMode } from './app/world'
import { InputManager, type FlightAction } from './app/input'
import { settings, lessonRecord, type Settings } from './app/settings'
import { drawHUD } from './app/hud'
import { drawInstruments, drawControls } from './app/instruments'
import { drawMap, drawProfile } from './app/maps'
import type { Frame } from './app/frame'
import { icons } from './app/icons'

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T
const esc = (s: string) => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))
const catVar = (c: LessonCategory) => `var(--cat-${c.toLowerCase().replace(' ', '')})`
const sevVar = ['var(--sev-info)', 'var(--sev-caution)', 'var(--sev-warning)']
const REPO = 'amalmehta/TopGunSimulator'

// MARK: - State

const world = new World()
const input = new InputManager()
const renderer = new THREE.WebGLRenderer({ canvas: $<HTMLCanvasElement>('gl'), antialias: true })
renderer.outputColorSpace = THREE.SRGBColorSpace
let session: FlightSession | null = null
let mode: SessionMode | null = null
let camera: CameraMode = 'Chase'
let paused = false
let result: { kind: 'passed' } | { kind: 'failed'; reason: string } | null = null
let crashed: string | null = null
let frame: Frame | null = null
let lastTick = performance.now()
let publishTimer = 0
let mapScale = 30
let raf = 0

const lessonOf = () => (mode?.kind === 'lesson' ? mode.lesson : null)

// MARK: - Home

function renderHome() {
  const done = lessonRecord.completed()
  const groups = ['Airwork', 'Takeoff & Landing', 'Top Gun']
  const card = (l: Lesson) => `
    <button class="card" data-lesson="${l.id}" style="--c:${catVar(l.category)}">
      <div class="row">
        <span class="tag" style="--c:${catVar(l.category)}">${icons[l.category].replace('<svg', '<svg width="13" height="13"')}${l.category}</span>
        <span style="flex:1"></span>
        ${done.has(l.id) ? `<span class="done" title="Passed">${icons.check.replace('<svg', '<svg width="16" height="16"')}</span>` : ''}
        <span class="muted">${l.aircraft === 'trainer' ? 'Trainer' : 'Fighter'}</span>
      </div>
      <h3>${l.number}. ${esc(l.title)}</h3>
      <p>${esc(l.summary)}</p>
    </button>`
  const ff = (k: AircraftKind) => {
    const s = specOf(k)
    return `<div class="ff-card"><h3>${s.name}</h3>
      <p>${k === 'trainer' ? `Forgiving high-wing trainer. Stalls at ~${s.vStallKt} kt, cruises at ${s.vCruiseKt} kt.` : 'Twin-engine fighter with fly-by-wire, afterburner and a 7.5 g limit.'}</p>
      <div class="row-btns"><button class="btn" data-free="${k}:ground">From the runway</button><button class="btn primary" data-free="${k}:air">In the air</button></div></div>`
  }
  const touch = matchMedia('(pointer: coarse)').matches && !navigator.getGamepads?.().some(Boolean)
  $('home').innerHTML = `<div class="home-inner home">
    <div class="home-header">
      <img class="logo" src="./favicon.svg" alt="" />
      <div><h1>Top Gun Simulator</h1><p>Learn to fly in the trainer, then take the fighter through the canyon and into a dogfight.</p></div>
      <div class="score"><b>${LESSONS.filter(l => done.has(l.id)).length}/${LESSONS.length}</b><span>lessons passed</span></div>
    </div>
    ${touch ? '<div class="notice">You fly with a keyboard or game controller. On a phone or tablet you can look around, but connect a keyboard or controller to fly.</div>' : ''}
    ${groups.map(g => `<h2>${g === 'Top Gun' ? 'Top Gun' : `Flight School · ${g}`}</h2>
      <div class="grid">${LESSONS.filter(l => categoryGroup(l.category) === g).map(card).join('')}</div>`).join('')}
    <h2>Free Flight</h2>
    <div class="ff-row">${ff('trainer')}${ff('fighter')}</div>
    <div class="home-footer">
      <button class="btn" id="home-help">${'Keyboard & gamepad controls'}</button>
      <button class="btn" id="home-settings">Settings</button>
    </div>
  </div>`
  $('home').querySelectorAll<HTMLButtonElement>('[data-lesson]').forEach(b => b.onclick = () => start({ kind: 'lesson', lesson: lessonById(b.dataset.lesson!)! }))
  $('home').querySelectorAll<HTMLButtonElement>('[data-free]').forEach(b => {
    const [k, where] = b.dataset.free!.split(':')
    b.onclick = () => start({ kind: 'free', aircraft: k as AircraftKind, airborne: where === 'air' })
  })
  $('home-help').onclick = () => openHelp()
  $('home-settings').onclick = () => openSettings()
}

// MARK: - Flight lifecycle

function start(m: SessionMode) {
  const s = settings.get()
  const sess = new FlightSession(m, s.autoRudder, settings.wind())
  sess.banditAI.skill = s.banditSkill
  session = sess
  mode = m
  input.throttle = sess.input.throttle
  world.load(sess)
  result = null; crashed = null; paused = false
  if (m.kind === 'lesson' && m.lesson.hasGates) camera = 'Chase'
  $('toasts').innerHTML = ''
  $('home').hidden = true
  $('flight').hidden = false
  document.body.classList.add('flying')
  $('flight-title').textContent = modeTitle(m)
  document.title = `${modeTitle(m)} · Top Gun Simulator`
  buildInstrumentPanel()
  applyLayout()
  $('touch-hint').hidden = !(matchMedia('(pointer: coarse)').matches && !navigator.getGamepads?.().some(Boolean))
  input.start()
  lastTick = performance.now()
  cancelAnimationFrame(raf)
  raf = requestAnimationFrame(tick)
  publish()
  renderSidebar(true)
  renderOverlay()
  updateToolbar()
}

function restart() { if (mode) start(mode) }

function end() {
  cancelAnimationFrame(raf)
  input.stop()
  session = null; mode = null; result = null; crashed = null
  $('flight').hidden = true
  $('home').hidden = false
  document.body.classList.remove('flying')
  document.title = 'Top Gun Simulator'
  renderHome()
}

function nextLesson() {
  const l = lessonOf()
  const i = l ? LESSONS.findIndex(x => x.id === l.id) : -1
  if (i >= 0 && i + 1 < LESSONS.length) start({ kind: 'lesson', lesson: LESSONS[i + 1] }); else end()
}

// MARK: - Frame loop

function tick(now: number) {
  raf = requestAnimationFrame(tick)
  const s = session
  if (!s) return
  const dt = Math.min((now - lastTick) / 1000, 0.1)
  lastTick = now
  s.paused = paused || result !== null
  if (!s.paused) {
    s.input = input.sample(dt, settings.get())
    s.advance(dt)
  }
  for (const e of s.drainEvents()) handleEvent(e)
  const set = settings.get()
  world.update(s, camera, set.fieldOfView, dt)
  resizeRenderer()
  renderer.render(world.scene, world.camera)

  publishTimer += dt
  if (publishTimer >= 1 / 30 || !frame) { publishTimer = 0; publish() }
  if (frame) {
    const vp = $('viewport')
    if (set.showHUD) drawHUD($<HTMLCanvasElement>('hud'), frame, s.player.spec, camera, world.camera.fov)
    else $<HTMLCanvasElement>('hud').getContext('2d')!.clearRect(0, 0, vp.clientWidth * 4, vp.clientHeight * 4)
  }
}

function resizeRenderer() {
  const vp = $('viewport')
  const w = vp.clientWidth, h = vp.clientHeight
  const c = renderer.domElement
  if (c.width !== Math.round(w * devicePixelRatio) || c.height !== Math.round(h * devicePixelRatio)) {
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
    renderer.setSize(w, h, false)
  }
  world.camera.aspect = w / Math.max(h, 1)
  world.camera.updateProjectionMatrix()
}

function publish() {
  const s = session
  if (!s) return
  const vp = $('viewport')
  const pending = s.gates.find(g => g.status === 'pending')
  const step = s.lesson?.currentStep, ctx = s.stepContext
  frame = {
    telemetry: s.telemetry,
    hints: settings.get().instructorLevel === 'off' ? [] : s.hints,
    lessonStatus: s.lesson?.status ?? null,
    lessonStepIndex: s.lesson?.stepIndex ?? 0,
    lessonProgressText: step?.progress && ctx ? step.progress(s.telemetry, ctx) : null,
    lessonHold: s.lesson?.holdTime ?? 0,
    gates: s.gates,
    trail: s.trail,
    banditTrail: s.banditTrail,
    banditPosition: s.bandit?.state.position ?? null,
    banditHeading: s.bandit?.state.headingDeg ?? 0,
    banditHealth: s.bandit?.state.health ?? 0,
    banditDistance: s.banditDistance,
    banditScreen: s.bandit && s.bandit.state.health > 0 ? world.project(s.bandit.state.position, vp.clientWidth, vp.clientHeight) : null,
    nextGateScreen: pending ? world.project(pending.center, vp.clientWidth, vp.clientHeight) : null,
    ammo: s.ammo,
    touchdown: s.player.lastTouchdown,
  }
  const set = settings.get()
  if (set.showInstruments) {
    drawInstruments(gaugeCanvases, frame.telemetry, s.player.spec)
    drawControls($<HTMLCanvasElement>('controls-canvas'), frame.telemetry)
    const t = frame.telemetry
    $('sys-line').textContent = `Flaps ${Math.round(t.flapsDeg)}°   Trim ${t.trim >= 0 ? '+' : ''}${Math.round(t.trim * 100)}${s.player.spec.hasRetractableGear ? (t.gearDown ? '   Gear ▼' : '   Gear ▲') : ''}`
  }
  if (set.showSidebar) {
    drawMap($<HTMLCanvasElement>('map'), frame, mapScale)
    drawProfile($<HTMLCanvasElement>('profile'), frame, lessonOf()?.category === 'Landing' || s.player.spec.kind === 'trainer')
    renderSidebar(false)
  }
}

// MARK: - Events and actions

function handleEvent(e: SessionEvent) {
  switch (e.kind) {
    case 'stepCompleted': toast(`✓ ${e.title}`, '#34c759'); break
    case 'lessonPassed': { const l = lessonOf(); if (l) lessonRecord.markCompleted(l.id); result = { kind: 'passed' }; renderOverlay(); break }
    case 'lessonFailed': result = { kind: 'failed', reason: e.reason }; renderOverlay(); break
    case 'crashed': crashed = e.reason; renderOverlay(); break
    case 'touchdown': { const r = e.report; toast(`Touchdown: ${r.grade} (${Math.round(r.sinkRateFpm)} fpm, ${Math.round(Math.abs(r.centerlineOffset))} m from centreline)`, r.grade === 'Hard' ? '#ff9500' : '#34c759'); break }
    case 'gatePassed': toast(`Gate ${e.index + 1} ✓`, '#34c759'); break
    case 'gateMissed': toast(`Missed gate ${e.index + 1}`, '#ff9500'); break
    case 'hitBandit': toast('Hit!', '#ffd60a'); break
    case 'gotHit': toast("You're taking hits: break turn!", '#ff3b30'); break
    case 'banditDestroyed': toast('Splash one! Bandit destroyed', '#34c759'); break
  }
}

function toast(text: string, color = '#8e8e93') {
  const el = document.createElement('div')
  el.className = 'toast'
  el.style.setProperty('--tc', color)
  el.textContent = text
  const box = $('toasts')
  box.appendChild(el)
  while (box.children.length > 4) box.firstElementChild!.remove()
  setTimeout(() => el.remove(), 3000)
}

function handleAction(a: FlightAction) {
  const s = session
  if (!s) return
  switch (a) {
    case 'flapsDown': s.setFlaps(1); announceFlaps(); break
    case 'flapsUp': s.setFlaps(-1); announceFlaps(); break
    case 'toggleGear':
      if (!s.player.spec.hasRetractableGear) { toast("The trainer's gear is fixed"); return }
      s.toggleGear(); toast(s.player.state.gearDown ? 'Gear down' : 'Gear up'); break
    case 'trimUp': s.adjustTrim(0.02); break
    case 'trimDown': s.adjustTrim(-0.02); break
    case 'nextCamera': camera = CAMERA_MODES[(CAMERA_MODES.indexOf(camera) + 1) % CAMERA_MODES.length]; updateToolbar(); break
    case 'togglePause': if (!result) { paused = !paused; renderOverlay(); updateToolbar() } break
    case 'toggleHelp': openHelp(); break
    case 'toggleSidebar': settings.set('showSidebar', !settings.get().showSidebar); break
    case 'toggleInstruments': settings.set('showInstruments', !settings.get().showInstruments); break
    case 'endFlight': end(); break
    case 'restart': restart(); break
  }
}
input.onAction = handleAction

function announceFlaps() {
  const s = session!
  const d = s.player.spec.flapDetents
  toast(`Flaps ${Math.round(s.player.state.flapsTarget * d[d.length - 1])}°`)
}

// MARK: - Overlay, toolbar, layout

function renderOverlay() {
  const o = $('overlay')
  let title = '', message = '', color = '', passed = false, isPause = false
  if (crashed && !result) { title = 'Crashed'; message = crashed; color = '#ff453a' }
  else if (result?.kind === 'passed') {
    title = 'Lesson passed'; color = '#30d158'; passed = true
    message = lessonOf()?.objectives.map(x => `✓ ${x}`).join('\n') ?? ''
    const td = session?.player.lastTouchdown
    if (td && lessonOf()?.category === 'Landing') message += `\n\nTouchdown: ${td.grade}, ${Math.round(td.sinkRateFpm)} fpm, ${Math.round(td.distanceFromThreshold)} m past the threshold, ${Math.round(Math.abs(td.centerlineOffset))} m off centreline`
  } else if (result?.kind === 'failed') { title = 'Lesson failed'; message = result.reason; color = '#ff9f0a' }
  else if (paused) { title = 'Paused'; message = 'Press P to resume.'; color = '#aeaeb2'; isPause = true }
  else { o.hidden = true; return }
  o.hidden = false
  o.innerHTML = `<h2 style="color:${color}">${esc(title)}</h2><p>${esc(message)}</p><div class="row-btns">
    ${isPause ? '<button class="btn primary" data-o="resume">Resume</button>' : `<button class="btn ${passed ? '' : 'primary'}" data-o="retry">Try again</button>`}
    ${passed && lessonOf() ? '<button class="btn primary" data-o="next">Next lesson</button>' : ''}
    <button class="btn" data-o="menu">Menu</button></div>`
  o.querySelectorAll<HTMLButtonElement>('[data-o]').forEach(b => b.onclick = () => {
    const k = b.dataset.o
    if (k === 'resume') { paused = false; renderOverlay(); updateToolbar() }
    else if (k === 'retry') restart()
    else if (k === 'next') nextLesson()
    else end()
  })
}

function buildToolbar() {
  $('btn-menu').innerHTML = icons.back
  $('btn-menu').onclick = end
  $('camera-seg').innerHTML = CAMERA_MODES.map(m => `<button data-cam="${m}" title="${m} camera (C)" role="radio">${m}</button>`).join('')
  $('camera-seg').querySelectorAll<HTMLButtonElement>('[data-cam]').forEach(b => b.onclick = () => { camera = b.dataset.cam as CameraMode; updateToolbar() })
  $('btn-restart').innerHTML = icons.restart
  $('btn-restart').onclick = restart
  $('btn-pause').onclick = () => handleAction('togglePause')
  $('btn-instruments').innerHTML = icons.gauge
  $('btn-instruments').onclick = () => handleAction('toggleInstruments')
  $('btn-sidebar').innerHTML = icons.sidebar
  $('btn-sidebar').onclick = () => handleAction('toggleSidebar')
  $('btn-help').innerHTML = icons.keyboard
  $('btn-help').onclick = openHelp
  $('btn-settings').innerHTML = icons.gear
  $('btn-settings').onclick = () => openSettings()
}

function updateToolbar() {
  $('camera-seg').querySelectorAll<HTMLButtonElement>('[data-cam]').forEach(b => {
    b.classList.toggle('on', b.dataset.cam === camera); b.setAttribute('aria-checked', String(b.dataset.cam === camera))
  })
  $('btn-pause').innerHTML = paused ? icons.play : icons.pause
  $('btn-pause').title = paused ? 'Resume (P)' : 'Pause (P)'
  const s = settings.get()
  $('btn-instruments').classList.toggle('on', s.showInstruments)
  $('btn-sidebar').classList.toggle('on', s.showSidebar)
}

function applyLayout() {
  const s = settings.get()
  $('instruments').hidden = !s.showInstruments
  $('sidebar').hidden = !s.showSidebar
  document.body.classList.toggle('no-sidebar', !s.showSidebar)
  document.body.classList.toggle('no-instruments', !s.showInstruments)
  updateToolbar()
}

let gaugeCanvases: HTMLCanvasElement[] = []
function buildInstrumentPanel() {
  const names = ['Airspeed', 'Attitude', 'Altimeter', 'Turn & slip', 'Heading', 'Vertical speed']
  $('instruments').innerHTML = names.map(n => `<div class="gauge"><canvas aria-label="${n}"></canvas><span>${n}</span></div>`).join('') +
    '<div class="controls-box"><canvas id="controls-canvas" aria-label="Stick and control surfaces"></canvas><div class="sys" id="sys-line"></div></div>'
  gaugeCanvases = [...$('instruments').querySelectorAll<HTMLCanvasElement>('.gauge canvas')]
}

// MARK: - Sidebar

let sidebarKey = ''
function renderSidebar(force: boolean) {
  const s = session
  if (!s || !frame) return
  const level = settings.get().instructorLevel
  const l = lessonOf()
  const key = JSON.stringify([frame.lessonStepIndex, frame.lessonProgressText, Math.round(frame.lessonHold * 10), frame.hints.map(h => h.id), level, l?.id])
  if (!force && key === sidebarKey) return
  sidebarKey = key
  let html = ''
  if (l) {
    const c = catVar(l.category)
    const i = frame.lessonStepIndex, step = l.steps[i]
    html += `<div class="panel" style="--c:${c}">
      <div class="row" style="display:flex;align-items:center"><span class="tag" style="--c:${c}">${l.category}</span><span style="flex:1"></span><span class="muted">Step ${Math.min(i + 1, l.steps.length)}/${l.steps.length}</span></div>
      <h2>${esc(l.title)}</h2>
      <div class="progress"><div style="width:${(i / l.steps.length) * 100}%"></div></div>
      ${step ? `<div class="step-card"><h3>${esc(step.title)}</h3><p>${esc(step.instruction)}</p>
        ${frame.lessonProgressText ? `<p class="mono tip">${esc(frame.lessonProgressText)}</p>` : ''}
        ${step.hold > 0 ? `<div style="display:flex;gap:6px;align-items:center;font-size:12px;color:var(--text-2)">Hold <div class="progress" style="flex:1"><div style="width:${Math.min(frame.lessonHold / step.hold, 1) * 100}%"></div></div>${step.hold}s</div>` : ''}
        ${step.tip ? `<p class="tip">🎓 ${esc(step.tip)}</p>` : ''}</div>` : ''}
      <ul class="step-list">${l.steps.map((st, k) => `<li class="${k < i ? 'done' : k === i ? 'current' : ''}"><span class="dot"></span>${esc(st.title)}</li>`).join('')}</ul>
    </div>`
  } else {
    const sp = s.player.spec
    html += `<div class="panel"><h2>Free flight</h2><b style="color:var(--text-2)">${sp.name}</b>
      <div class="specs"><span>Stall</span><span>${sp.vStallKt} kt</span><span>Rotate</span><span>${sp.vRotateKt} kt</span><span>Best climb</span><span>${sp.vClimbKt} kt</span>
      <span>Approach</span><span>${sp.vApproachKt} kt</span><span>Cruise</span><span>${sp.vCruiseKt} kt</span><span>Never exceed</span><span>${sp.vNeKt} kt</span></div>
      <p class="muted" style="font-weight:400">Runway 36 is 2,400 m long, heading north. The canyon starts 7 km north of the field. The PAPI lights left of the runway show two white and two red when you're on a 3° glidepath.</p></div>`
  }
  if (level !== 'off') {
    html += `<div class="panel" style="margin-top:12px"><h3 style="margin:0;font-size:16px">Instructor</h3>`
    if (!frame.hints.length) html += `<p class="muted" style="font-weight:400;margin:0">Looking good. I'll speak up if something needs your attention.</p>`
    for (const h of frame.hints.slice(0, 4)) {
      html += `<div class="hint" style="--sc:${sevVar[h.severity]}"><b>${esc(h.text)}</b>${level === 'explain' ? `<small>${esc(h.why)}</small>` : ''}</div>`
    }
    html += '</div>'
  }
  $('side-panels').innerHTML = html
}

// MARK: - Dialogs

function openHelp() {
  const rows: [string, string][] = [
    ['S / ↓', 'Stick back: nose up'], ['W / ↑', 'Stick forward: nose down'], ['A D / ← →', 'Roll left / right (ailerons)'],
    ['Q / E', 'Rudder left / right (yaw)'], ['R / F', 'Throttle up / down (hold)'], ['[ / ]', 'Flaps up / down'],
    [', / .', 'Trim nose down / nose up'], ['G', 'Gear up / down (fighter)'], ['B', 'Wheel brakes (hold)'], ['Space', 'Guns (fighter)'],
    ['C', 'Next camera; drag the view to orbit, scroll to zoom'], ['P', 'Pause'], ['I / M', 'Toggle instruments / sidebar'],
    ['\\', 'Restart'], ['Esc', 'End flight'], ['H', 'This help'], ['⌘, / Ctrl+,', 'Settings'],
  ]
  const d = $<HTMLDialogElement>('dlg-help')
  d.innerHTML = `<h2>Controls</h2><div class="help-grid">${rows.map(([k, a]) => `<kbd>${esc(k)}</kbd><span>${esc(a)}</span>`).join('')}</div>
    <p class="muted" style="font-weight:400">Game controller: left stick = stick, right stick = rudder, triggers = throttle, A = guns, B = brakes.</p>
    <div class="dlg-actions"><button class="btn primary" autofocus>Done</button></div>`
  d.querySelector('button')!.onclick = () => d.close()
  if (!d.open) d.showModal()
}

type Tab = 'Flying' | 'Instructor' | 'Display' | 'World'
function openSettings(tab: Tab = 'Flying') {
  const d = $<HTMLDialogElement>('dlg-settings')
  const s = settings.get()
  const check = (k: keyof Settings, label: string) => `<label class="field"><span>${label}</span><input type="checkbox" data-k="${k}" ${s[k] ? 'checked' : ''}></label>`
  const range = (k: keyof Settings, label: string, min: number, max: number, step: number, unit: (v: number) => string) =>
    `<label class="field"><span>${label}</span><input type="range" data-k="${k}" min="${min}" max="${max}" step="${step}" value="${s[k]}"><span class="val" data-v="${k}">${unit(s[k] as number)}</span></label>`
  const units: Partial<Record<keyof Settings, (v: number) => string>> = {
    stickSensitivity: v => v.toFixed(1) + '×', keyboardCentering: v => v.toFixed(1) + '×', fieldOfView: v => `${v}°`,
    windSpeedKt: v => `${v} kt`, windFromDeg: v => `${v}°`, turbulence: v => `${Math.round(v * 100)}%`, banditSkill: v => `${Math.round(v * 100)}%`,
  }
  const body: Record<Tab, string> = {
    Flying: check('autoRudder', 'Auto-rudder (keeps turns coordinated and the takeoff roll straight)') + check('invertPitch', 'Invert pitch (W / ↑ pulls the nose up)') +
      range('stickSensitivity', 'Stick sensitivity', 0.4, 1.5, 0.1, units.stickSensitivity!) + range('keyboardCentering', 'Keyboard re-centering', 0.3, 2, 0.1, units.keyboardCentering!) +
      '<p class="muted" style="font-weight:400">A game controller works too: left stick flies, right stick is rudder, triggers set the throttle, A fires.</p>',
    Instructor: `<label class="field"><span>Instructor</span><select data-k="instructorLevel">${(['off', 'hints', 'explain'] as const).map(v =>
      `<option value="${v}" ${s.instructorLevel === v ? 'selected' : ''}>${{ off: 'Off', hints: 'Hints', explain: 'Hints + why' }[v]}</option>`).join('')}</select></label>
      <p class="muted" style="font-weight:400">“Hints + why” explains the aerodynamics behind each tip. Warnings (stall, sink rate) flash on the HUD unless the instructor is off.</p>
      <button class="btn" id="reset-progress">Reset lesson progress…</button>`,
    Display: check('showHUD', 'Head-up display') + check('showInstruments', 'Instrument panel (I)') + check('showSidebar', 'Map, profile and lesson sidebar (M)') +
      `<label class="field"><span>Units</span><select data-k="metricUnits"><option value="false" ${!s.metricUnits ? 'selected' : ''}>Aviation (kt, ft, fpm)</option><option value="true" ${s.metricUnits ? 'selected' : ''}>Metric (km/h, m, m/s)</option></select></label>` +
      range('fieldOfView', 'Field of view', 40, 95, 1, units.fieldOfView!),
    World: range('windSpeedKt', 'Wind speed', 0, 30, 1, units.windSpeedKt!) + range('windFromDeg', 'Wind from', 0, 360, 10, units.windFromDeg!) +
      range('turbulence', 'Turbulence', 0, 1, 0.05, units.turbulence!) + range('banditSkill', 'Bandit skill', 0.2, 1, 0.05, units.banditSkill!) +
      '<p class="muted" style="font-weight:400">A crosswind makes landings harder: point into the wind and use rudder to line up at touchdown. Wind changes apply to the next flight.</p>',
  }
  d.innerHTML = `<h2>Settings</h2><div class="tabs">${(Object.keys(body) as Tab[]).map(t => `<button data-tab="${t}" class="${t === tab ? 'on' : ''}">${t}</button>`).join('')}</div>
    <div>${body[tab]}</div><div class="dlg-actions"><button class="btn primary" id="settings-done">Done</button></div>`
  d.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach(b => b.onclick = () => openSettings(b.dataset.tab as Tab))
  d.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[data-k]').forEach(el => {
    const k = el.dataset.k as keyof Settings
    el.oninput = () => {
      let v: unknown
      if (el instanceof HTMLInputElement && el.type === 'checkbox') v = el.checked
      else if (el instanceof HTMLInputElement) { v = Number(el.value); const out = d.querySelector(`[data-v="${k}"]`); if (out) out.textContent = units[k]!(v as number) }
      else v = k === 'metricUnits' ? el.value === 'true' : el.value
      settings.set(k, v as never)
    }
  })
  const reset = d.querySelector<HTMLButtonElement>('#reset-progress')
  if (reset) reset.onclick = () => { if (confirm('Clear all passed lessons?')) { lessonRecord.reset(); if (!session) renderHome() } }
  $('settings-done').onclick = () => d.close()
  if (!d.open) d.showModal()
}

function openFeedback() {
  const d = $<HTMLDialogElement>('dlg-feedback')
  d.innerHTML = `<h2>Feedback</h2>
    <div class="tabs" id="fb-kind"><button class="on" data-kind="Idea">Idea</button><button data-kind="Bug">Bug</button><button data-kind="Flight model">Flight model</button></div>
    <textarea id="fb-text" placeholder="What should be better?"></textarea>
    <p class="muted" style="font-weight:400">Opens a new GitHub issue with your note filled in. You review it there before posting.</p>
    <div class="dlg-actions"><button class="btn" id="fb-cancel">Cancel</button><button class="btn primary" id="fb-send" disabled>Open GitHub issue</button></div>`
  let kind = 'Idea'
  d.querySelectorAll<HTMLButtonElement>('[data-kind]').forEach(b => b.onclick = () => {
    kind = b.dataset.kind!; d.querySelectorAll('[data-kind]').forEach(x => x.classList.toggle('on', x === b))
  })
  const text = d.querySelector<HTMLTextAreaElement>('#fb-text')!
  const send = d.querySelector<HTMLButtonElement>('#fb-send')!
  text.oninput = () => { send.disabled = !text.value.trim() }
  send.onclick = () => {
    const title = `[${kind}] ${text.value.trim().split('\n')[0].slice(0, 70)}`
    const body = `${text.value.trim()}\n\n---\nSent from the web app (${mode ? modeTitle(mode) : 'home screen'}).`
    window.open(`https://github.com/${REPO}/issues/new?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`, '_blank', 'noopener')
    d.close()
  }
  d.querySelector<HTMLButtonElement>('#fb-cancel')!.onclick = () => d.close()
  d.showModal()
  text.focus()
}

// MARK: - Mouse orbit, zoom, global keys

const gl = $<HTMLCanvasElement>('gl')
let dragging: { x: number; y: number } | null = null
gl.addEventListener('pointerdown', e => { dragging = { x: e.clientX, y: e.clientY }; gl.setPointerCapture(e.pointerId) })
gl.addEventListener('pointermove', e => {
  if (!dragging) return
  const dx = e.clientX - dragging.x, dy = e.clientY - dragging.y
  dragging = { x: e.clientX, y: e.clientY }
  if (camera !== 'Orbit') { camera = 'Orbit'; updateToolbar() }
  world.orbitAzimuth -= dx * 0.01
  world.orbitElevation = Math.min(1.4, Math.max(-0.3, world.orbitElevation + dy * 0.01))
})
gl.addEventListener('pointerup', () => { dragging = null })
gl.addEventListener('wheel', e => { e.preventDefault(); world.orbitDistanceScale = Math.min(12, Math.max(0.5, world.orbitDistanceScale * (1 + e.deltaY * 0.002))) }, { passive: false })
$('zoom-in').onclick = () => { mapScale = Math.max(5, mapScale / 1.6) }
$('zoom-out').onclick = () => { mapScale = Math.min(250, mapScale * 1.6) }
$('feedback-tab').onclick = openFeedback
window.addEventListener('keydown', e => {
  if ((e.metaKey || e.ctrlKey) && e.key === ',') { e.preventDefault(); openSettings() }
  if (!session && e.key.toLowerCase() === 'h' && !(e.target instanceof HTMLTextAreaElement)) openHelp()
})
settings.onChange(() => {
  const s = settings.get()
  if (session) { session.player.autoRudder = s.autoRudder; session.banditAI.skill = s.banditSkill; applyLayout(); sidebarKey = '' }
})

// MARK: - Boot

buildToolbar()
renderHome()
const params = new URLSearchParams(location.search)
const cam = params.get('camera') as CameraMode | null
if (cam && CAMERA_MODES.includes(cam)) camera = cam
const startId = params.get('start')
if (startId) {
  const free: Record<string, SessionMode> = {
    'free-trainer': { kind: 'free', aircraft: 'trainer', airborne: false }, 'free-fighter': { kind: 'free', aircraft: 'fighter', airborne: false },
    'air-trainer': { kind: 'free', aircraft: 'trainer', airborne: true }, 'air-fighter': { kind: 'free', aircraft: 'fighter', airborne: true },
  }
  const l = lessonById(startId)
  const m = free[startId] ?? (l ? { kind: 'lesson', lesson: l } as SessionMode : null)
  if (m) start(m)
}
