// The 3D world (port of WorldScene.swift): terrain, airport, PAPI, gates, tracers, explosions, cameras.
import * as THREE from 'three'
import { Terrain } from '../core/environment'
import { SeededRandom, Vec3, clamp, deg, smoothstep } from '../core/math'
import type { AircraftState } from '../core/aircraft'
import type { FlightSession } from '../core/session'
import { AircraftModel } from './models'

export type CameraMode = 'Chase' | 'Cockpit' | 'Orbit' | 'Tower'
export const CAMERA_MODES: CameraMode[] = ['Chase', 'Cockpit', 'Orbit', 'Tower']

const HORIZON = 0xd6e8f7, ZENITH = 0x4a8fe0

/** Ground colour by height and slope; shared with the 2D map. */
export function groundColor(h: number, slope: number, x: number, z: number): [number, number, number] {
  const noise = 0.04 * Math.sin(x * 0.013) * Math.cos(z * 0.011) + 0.03 * Math.sin(x * 0.051 + z * 0.037)
  const lerp = (a: number[], b: number[], t: number) => a.map((v, i) => v + (b[i] - v) * t)
  let c: number[]
  if (h < 2) c = [0.36, 0.52, 0.27]
  else if (h < 250) c = lerp([0.38, 0.54, 0.28], [0.28, 0.42, 0.22], h / 250)
  else if (h < 700) c = lerp([0.28, 0.42, 0.22], [0.48, 0.42, 0.33], (h - 250) / 450)
  else c = lerp([0.48, 0.42, 0.33], [0.92, 0.93, 0.96], smoothstep(900, 1150, h))
  if (slope > 0.25) c = lerp(c, [0.45, 0.4, 0.34], Math.min(1, (slope - 0.25) * 2.5))
  return [c[0] + noise, c[1] + noise, c[2] + noise]
}

export class World {
  scene = new THREE.Scene()
  camera = new THREE.PerspectiveCamera(65, 1, 0.25, 60_000)
  player: AircraftModel | null = null
  bandit: AircraftModel | null = null
  orbitAzimuth = 0.6
  orbitElevation = 0.25
  orbitDistanceScale = 1.6
  private gateMeshes: THREE.Mesh[] = []
  private papi: THREE.MeshBasicMaterial[] = []
  private tracer: THREE.Mesh
  private banditTracer: THREE.Mesh
  private smoothed: THREE.Vector3 | null = null
  private explosions: { group: THREE.Group; born: number; key: string }[] = []

  constructor() {
    this.scene.background = this.skyTexture()
    this.scene.fog = new THREE.Fog(HORIZON, 7000, 32_000)
    const sun = new THREE.DirectionalLight(0xfff4e0, 2.4)
    sun.position.set(-0.5, 0.8, 0.4)
    this.scene.add(sun, new THREE.HemisphereLight(0xb8cce6, 0x5a6b48, 1.1))
    this.buildTerrain()
    this.buildAirport()
    this.tracer = this.makeTracer(0xffe070)
    this.banditTracer = this.makeTracer(0xff5050)
    this.scene.add(this.camera)
  }

  load(session: FlightSession) {
    for (const m of [this.player, this.bandit]) if (m) this.scene.remove(m.root)
    for (const g of this.gateMeshes) this.scene.remove(g)
    for (const e of this.explosions) this.scene.remove(e.group)
    this.explosions = []
    this.gateMeshes = []
    this.player = new AircraftModel(session.player.spec, session.player.spec.kind === 'trainer' ? 0xc8202a : 0x8c98a4)
    this.scene.add(this.player.root)
    this.bandit = null
    if (session.bandit) {
      this.bandit = new AircraftModel(session.bandit.spec, 0x6e2a2a)
      this.scene.add(this.bandit.root)
    }
    for (const g of session.gates) {
      const mesh = new THREE.Mesh(new THREE.TorusGeometry(g.radius, 1.6, 12, 48), new THREE.MeshBasicMaterial({ color: 0xff8c1a }))
      mesh.position.set(g.center.x, g.center.y, g.center.z)
      // Torus lies in its XY plane with its axis on Z; point Z along the direction of travel.
      mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), new THREE.Vector3(g.normal.x, g.normal.y, g.normal.z))
      this.scene.add(mesh)
      this.gateMeshes.push(mesh)
    }
    this.smoothed = null
  }

  update(session: FlightSession, mode: CameraMode, fov: number, dt: number) {
    if (!this.player) return
    const t = session.time
    this.player.update(session.player.state, t)
    if (session.bandit && this.bandit) {
      this.bandit.update(session.bandit.state, t)
      if (session.bandit.state.health <= 0) this.explode(this.bandit.root.position, 'bandit', t)
    }
    if (session.player.state.crashed) this.explode(this.player.root.position, 'player', t)
    session.gates.forEach((g, i) => {
      const m = this.gateMeshes[i]
      if (m) (m.material as THREE.MeshBasicMaterial).color.setHex(g.status === 'pending' ? 0xff8c1a : g.status === 'passed' ? 0x30d158 : 0x8e8e93)
    })
    this.updatePAPI(session.player.state.position)
    this.updateTracer(this.tracer, session.player.state, session.firing, t)
    if (session.bandit) this.updateTracer(this.banditTracer, session.bandit.state, session.banditFiring, t)
    else this.banditTracer.visible = false
    this.updateExplosions(t)
    this.updateCamera(session, mode, fov, dt)
  }

  /** World point → CSS pixels in a viewport of the given size (null if behind the camera). */
  project(p: Vec3, width: number, height: number) {
    const v = new THREE.Vector3(p.x, p.y, p.z)
    const toPoint = v.clone().sub(this.camera.position)
    const fwd = new THREE.Vector3()
    this.camera.getWorldDirection(fwd)
    if (toPoint.dot(fwd) <= 0) return null
    v.project(this.camera)
    return { x: (v.x + 1) / 2 * width, y: (1 - v.y) / 2 * height }
  }

  private updateCamera(session: FlightSession, mode: CameraMode, fov: number, dt: number) {
    const model = this.player!
    const s = session.player.state
    const pos = new THREE.Vector3(s.position.x, s.position.y, s.position.z)
    const f = s.forward, u = s.up
    const fwd = new THREE.Vector3(f.x, f.y, f.z), up = new THREE.Vector3(u.x, u.y, u.z)
    const dist = model.chaseDistance
    const cam = this.camera
    cam.fov = fov
    cam.near = 0.5
    cam.up.set(0, 1, 0)

    if (mode === 'Cockpit') {
      model.root.updateMatrixWorld()
      cam.position.copy(model.cockpitEye.clone().applyMatrix4(model.root.matrixWorld))
      cam.quaternion.copy(model.root.quaternion)
      cam.near = 0.1
      this.smoothed = null
    } else if (mode === 'Chase') {
      const level = new THREE.Vector3(fwd.x, fwd.y * 0.8, fwd.z).normalize()
      const target = pos.clone().addScaledVector(level, -dist).addScaledVector(new THREE.Vector3(0, 1, 0), dist * 0.22).addScaledVector(up, dist * 0.08)
      const k = 1 - Math.exp(-dt * 8)
      this.smoothed = this.smoothed ? this.smoothed.lerp(target, k) : target
      cam.position.copy(this.smoothed)
      cam.lookAt(pos.clone().addScaledVector(fwd, dist * 0.6))
    } else if (mode === 'Orbit') {
      const r = dist * this.orbitDistanceScale
      const a = this.orbitAzimuth, e = this.orbitElevation
      cam.position.set(pos.x + Math.sin(a) * Math.cos(e) * r, pos.y + Math.sin(e) * r, pos.z + Math.cos(a) * Math.cos(e) * r)
      cam.lookAt(pos)
      this.smoothed = null
    } else {
      cam.position.set(120, 35, 150)
      cam.lookAt(pos)
      cam.fov = clamp(deg(2 * Math.atan(40 / pos.distanceTo(cam.position))), 4, fov)
      this.smoothed = null
    }
    const ground = Terrain.height(cam.position.x, cam.position.z) + 1.5
    if (cam.position.y < ground) cam.position.y = ground
    cam.updateProjectionMatrix()
  }

  // MARK: Effects

  private makeTracer(color: number) {
    const geo = new THREE.CylinderGeometry(0.25, 0.25, 900, 6)
    geo.rotateX(Math.PI / 2)
    geo.translate(0, 0, -460)
    const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false }))
    m.visible = false
    this.scene.add(m)
    return m
  }

  private updateTracer(m: THREE.Mesh, s: AircraftState, firing: boolean, time: number) {
    m.visible = firing && Math.trunc(time * 30) % 2 === 1
    if (!firing) return
    const p = s.position.add(s.forward.mul(6)).add(s.up.mul(0.5))
    m.position.set(p.x, p.y, p.z)
    m.quaternion.set(s.orientation.x, s.orientation.y, s.orientation.z, s.orientation.w)
  }

  private explode(at: THREE.Vector3, key: string, time: number) {
    if (this.explosions.some(e => e.key === key)) return
    const group = new THREE.Group()
    group.position.copy(at)
    const fire = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshBasicMaterial({ color: 0xff8a20, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }))
    const smoke = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshLambertMaterial({ color: 0x262626, transparent: true, opacity: 0.6, depthWrite: false }))
    fire.name = 'fire'; smoke.name = 'smoke'
    group.add(fire, smoke)
    this.scene.add(group)
    this.explosions.push({ group, born: time, key })
  }

  private updateExplosions(time: number) {
    for (const e of this.explosions) {
      const age = time - e.born
      const fire = e.group.getObjectByName('fire') as THREE.Mesh, smoke = e.group.getObjectByName('smoke') as THREE.Mesh
      fire.scale.setScalar(4 + age * 40)
      ;(fire.material as THREE.MeshBasicMaterial).opacity = Math.max(0, 1 - age / 1.2)
      smoke.scale.setScalar(6 + age * 12)
      smoke.position.y = age * 6
      ;(smoke.material as THREE.MeshLambertMaterial).opacity = Math.max(0, 0.6 - age / 12)
    }
  }

  // MARK: World building

  private skyTexture() {
    const c = document.createElement('canvas')
    c.width = 2; c.height = 512
    const g = c.getContext('2d')!
    const grad = g.createLinearGradient(0, 0, 0, 512)
    grad.addColorStop(0, '#' + ZENITH.toString(16))
    grad.addColorStop(0.5, '#' + HORIZON.toString(16))
    grad.addColorStop(1, '#8fa88a')
    g.fillStyle = grad
    g.fillRect(0, 0, 2, 512)
    const tex = new THREE.CanvasTexture(c)
    tex.mapping = THREE.EquirectangularReflectionMapping
    tex.colorSpace = THREE.SRGBColorSpace
    return tex
  }

  private buildTerrain() {
    const minX = -22_000, maxX = 22_000, minZ = -32_000, maxZ = 12_000, step = 125
    const nx = (maxX - minX) / step + 1, nz = (maxZ - minZ) / step + 1
    const positions = new Float32Array(nx * nz * 3), normals = new Float32Array(nx * nz * 3), colors = new Float32Array(nx * nz * 3)
    let k = 0
    for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
      const x = minX + i * step, z = minZ + j * step
      const h = Terrain.height(x, z), n = Terrain.normal(x, z)
      positions.set([x, h - 0.6, z], k)
      normals.set([n.x, n.y, n.z], k)
      colors.set(groundColor(h, 1 - n.y, x, z), k)
      k += 3
    }
    const indices = new Uint32Array((nx - 1) * (nz - 1) * 6)
    k = 0
    for (let j = 0; j < nz - 1; j++) for (let i = 0; i < nx - 1; i++) {
      const a = j * nx + i, b = a + 1, c = a + nx, d = c + 1
      indices.set([a, c, b, b, c, d], k); k += 6
    }
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3))
    geo.setAttribute('normal', new THREE.BufferAttribute(normals, 3))
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3))
    geo.setIndex(new THREE.BufferAttribute(indices, 1))
    this.scene.add(new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true })))
    const apron = new THREE.Mesh(new THREE.PlaneGeometry(400_000, 400_000), new THREE.MeshLambertMaterial({ color: 0x6e8f55 }))
    apron.rotation.x = -Math.PI / 2
    apron.position.set(0, -3, -10_000)
    this.scene.add(apron)
  }

  private buildAirport() {
    const airport = new THREE.Group()
    const L = Terrain.runwayLength, W = Terrain.runwayWidth
    const flat = (color: number) => new THREE.MeshLambertMaterial({ color })
    const glow = (color: number) => new THREE.MeshBasicMaterial({ color })
    const add = (geo: THREE.BufferGeometry, m: THREE.Material, x: number, y: number, z: number) => {
      const mesh = new THREE.Mesh(geo, m); mesh.position.set(x, y, z); airport.add(mesh); return mesh
    }
    add(new THREE.BoxGeometry(W, 0.4, L), flat(0x3a3d42), 0, -0.2, 0)
    const white = flat(0xededed)
    const stripe = (x: number, z: number, w: number, l: number) => add(new THREE.BoxGeometry(w, 0.02, l), white, x, 0.01, z)
    for (let z = -L / 2 + 60; z < L / 2 - 60; z += 60) stripe(0, z, 0.9, 30)
    for (const end of [-1, 1]) {
      for (let i = 0; i < 8; i++) stripe(-W / 2 + 4 + i * 5.2 + (i >= 4 ? 2 : 0), end * (L / 2 - 25), 1.8, 30)
      for (let i = 0; i < 3; i++) for (const x of [-10, 10]) stripe(x, end * (L / 2 - 330 - i * 12), 3, 8)
    }
    stripe(-W / 2 + 1, 0, 0.9, L)
    stripe(W / 2 - 1, 0, 0.9, L)
    for (const [text, z, rot] of [['36', L / 2 - 95, 0], ['18', -L / 2 + 95, Math.PI]] as const) {
      const c = document.createElement('canvas'); c.width = 256; c.height = 256
      const g = c.getContext('2d')!
      g.fillStyle = '#ededed'; g.font = 'bold 200px sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'
      g.fillText(text, 128, 138)
      const tex = new THREE.CanvasTexture(c)
      const m = add(new THREE.PlaneGeometry(18, 18), new THREE.MeshLambertMaterial({ map: tex, transparent: true }), 0, 0.03, z)
      m.rotation.set(-Math.PI / 2, 0, rot)
    }
    const lightGeo = new THREE.SphereGeometry(0.35, 6, 6), lightMat = glow(0xfff3c0)
    for (let z = -L / 2; z <= L / 2; z += 60) for (const x of [-W / 2 - 2, W / 2 + 2]) add(lightGeo, lightMat, x, 0.3, z)
    for (let i = 1; i <= 10; i++) for (const dx of [-3, 0, 3]) add(lightGeo, lightMat, dx, 0.6, L / 2 + i * 30)
    for (let i = 0; i < 4; i++) {
      const m = glow(0xffffff)
      add(new THREE.BoxGeometry(1.6, 1.0, 0.6), m, -W / 2 - 15 - i * 9, 0.6, L / 2 - 300)
      this.papi.push(m)
    }
    const concrete = flat(0xc8c4bc), roof = flat(0x5e6b78)
    add(new THREE.BoxGeometry(6, 28, 6), concrete, 120, 14, 150)
    add(new THREE.BoxGeometry(10, 5, 10), flat(0x2a4058), 120, 30, 150)
    for (let i = 0; i < 4; i++) add(new THREE.BoxGeometry(40, 14, 36), [roof, concrete, roof, concrete, roof, concrete][i % 2 ? 1 : 0], 170, 7, -200 + i * 55)
    add(new THREE.BoxGeometry(110, 0.3, 300), flat(0x55585d), 110, -0.15, -100)
    this.scene.add(airport)
    this.buildTrees()
  }

  private buildTrees() {
    const rng = new SeededRandom(7)
    const count = 700
    const cones = new THREE.InstancedMesh(new THREE.ConeGeometry(4, 12, 7), new THREE.MeshLambertMaterial({ color: 0x2f5a2a }), count)
    const trunks = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.6, 0.6, 3, 5), new THREE.MeshLambertMaterial({ color: 0x5a4030 }), count)
    const m = new THREE.Matrix4(), q = new THREE.Quaternion()
    let placed = 0
    while (placed < count) {
      const x = rng.signedUnit() * 9000, z = rng.signedUnit() * 9000 - 2000
      if (Math.abs(x) < 250 && Math.abs(z) < 1700) continue
      if (x > 60 && x < 260 && z > -300 && z < 220) continue
      const h = Terrain.height(x, z)
      const s = 0.7 + 0.6 * (rng.signedUnit() + 1) / 2
      m.compose(new THREE.Vector3(x, h - 0.6 + 9 * s, z), q, new THREE.Vector3(s, s, s)); cones.setMatrixAt(placed, m)
      m.compose(new THREE.Vector3(x, h - 0.6 + 1.5 * s, z), q, new THREE.Vector3(s, s, s)); trunks.setMatrixAt(placed, m)
      placed++
    }
    this.scene.add(cones, trunks)
  }

  private updatePAPI(p: Vec3) {
    const dz = p.z - (Terrain.runwaySouthEnd - 300)
    const angle = dz > 0 ? deg(Math.atan2(p.y, dz)) : 90
    const thresholds = [3.5, 3.17, 2.83, 2.5]
    this.papi.forEach((m, i) => m.color.setHex(angle > thresholds[i] ? 0xffffff : 0xff2020))
  }
}
