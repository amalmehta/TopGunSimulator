// Preferences and lesson progress in localStorage (port of AppSettings.swift).
import { WindModel } from '../core/environment'
import { Units } from '../core/math'

export type InstructorLevel = 'off' | 'hints' | 'explain'

export interface Settings {
  autoRudder: boolean
  invertPitch: boolean
  stickSensitivity: number
  keyboardCentering: number
  instructorLevel: InstructorLevel
  showHUD: boolean
  showInstruments: boolean
  showSidebar: boolean
  metricUnits: boolean
  fieldOfView: number
  windSpeedKt: number
  windFromDeg: number
  turbulence: number
  banditSkill: number
}

export const DEFAULTS: Settings = {
  autoRudder: true, invertPitch: false, stickSensitivity: 1, keyboardCentering: 1, instructorLevel: 'explain',
  showHUD: true, showInstruments: true, showSidebar: true, metricUnits: false, fieldOfView: 65,
  windSpeedKt: 0, windFromDeg: 360, turbulence: 0, banditSkill: 0.6,
}

const KEY = 'topgun.settings', LESSONS_KEY = 'topgun.completedLessons'
const listeners = new Set<() => void>()

function read<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v ? { ...fallback, ...JSON.parse(v) } as T : fallback } catch { return fallback }
}
function write(key: string, value: unknown) {
  try { localStorage.setItem(key, JSON.stringify(value)) } catch { /* private mode: keep in memory only */ }
}

let current: Settings = read(KEY, DEFAULTS)

export const settings = {
  get: () => current,
  set<K extends keyof Settings>(key: K, value: Settings[K]) {
    current = { ...current, [key]: value }
    write(KEY, current)
    listeners.forEach(l => l())
  },
  onChange(l: () => void) { listeners.add(l); return () => listeners.delete(l) },
  wind: () => new WindModel(current.windSpeedKt * Units.knot, current.windFromDeg, current.turbulence),
}

let completed: string[] = (() => { try { return JSON.parse(localStorage.getItem(LESSONS_KEY) ?? '[]') } catch { return [] } })()
export const lessonRecord = {
  completed: () => new Set(completed),
  markCompleted(id: string) { if (!completed.includes(id)) { completed = [...completed, id].sort(); write(LESSONS_KEY, completed) } },
  reset() { completed = []; write(LESSONS_KEY, completed) },
}

export const fmt = {
  altitude: (ft: number) => current.metricUnits ? `${Math.round(ft * Units.foot)} m` : `${Math.round(ft)} ft`,
  speed: (kt: number) => current.metricUnits ? `${Math.round(kt * Units.knot * 3.6)} km/h` : `${Math.round(kt)} kt`,
  vertical: (fpm: number) => current.metricUnits ? `${fpm * Units.feetPerMinute >= 0 ? '+' : ''}${(fpm * Units.feetPerMinute).toFixed(1)} m/s` : `${Math.round(fpm)} fpm`,
}
