// 3D aircraft built from primitives, with hinged control surfaces (port of AircraftModels.swift).
import * as THREE from 'three'
import type { AircraftSpec, AircraftState } from '../core/aircraft'

const mat = (color: number, o: Partial<THREE.MeshStandardMaterialParameters> = {}) =>
  new THREE.MeshStandardMaterial({ color, roughness: 0.5, metalness: 0.2, ...o })

export class AircraftModel {
  root = new THREE.Group()
  leftAileron = new THREE.Group()
  rightAileron = new THREE.Group()
  elevators: THREE.Object3D[] = []
  rudders: THREE.Object3D[] = []
  flaps: THREE.Object3D[] = []
  propeller: THREE.Object3D | null = null
  propDisc: THREE.Mesh | null = null
  afterburners: THREE.Mesh[] = []
  gearNodes: THREE.Object3D[] = []
  cockpitEye = new THREE.Vector3()
  chaseDistance = 18

  constructor(public spec: AircraftSpec, paint: number) {
    if (spec.kind === 'trainer') this.buildTrainer(paint)
    else this.buildFighter(paint)
    this.root.traverse(o => { if ((o as THREE.Mesh).isMesh) o.castShadow = false })
  }

  update(s: AircraftState, time: number) {
    this.root.position.set(s.position.x, s.position.y, s.position.z)
    this.root.quaternion.set(s.orientation.x, s.orientation.y, s.orientation.z, s.orientation.w)
    const f = s.surfaces
    // Positive hinge rotation about X moves the trailing edge down; about Y moves it right.
    this.rightAileron.rotation.x = -f.aileron * 0.35
    this.leftAileron.rotation.x = f.aileron * 0.35
    for (const e of this.elevators) e.rotation.x = -f.elevator * 0.4
    for (const r of this.rudders) r.rotation.y = f.rudder * 0.45
    for (const fl of this.flaps) fl.rotation.x = s.flaps * 0.6
    if (this.propeller) {
      const rpm = 0.15 + s.engine * 0.85
      this.propeller.rotation.z = (time * 40 * rpm) % (Math.PI * 2)
      this.propeller.visible = s.engine < 0.3
      if (this.propDisc) this.propDisc.visible = s.engine >= 0.3
    }
    const burner = s.engine > 0.95 ? 0.6 + 0.4 * Math.sin(time * 50) : 0
    for (const ab of this.afterburners) { ab.visible = burner > 0; (ab.material as THREE.MeshBasicMaterial).opacity = burner }
    for (const g of this.gearNodes) { g.visible = s.gear >= 0.5; g.scale.y = Math.max(s.gear, 0.01) }
  }

  private add(geo: THREE.BufferGeometry, m: THREE.Material, x = 0, y = 0, z = 0, parent: THREE.Object3D = this.root) {
    const mesh = new THREE.Mesh(geo, m)
    mesh.position.set(x, y, z)
    parent.add(mesh)
    return mesh
  }

  /** Cylinder along the body Z axis with the given front (-Z) and back (+Z) radii. */
  private tube(rFront: number, rBack: number, len: number, m: THREE.Material, z: number, y = 0) {
    const mesh = this.add(new THREE.CylinderGeometry(rBack, rFront, len, 24), m, 0, y, z)
    mesh.rotation.x = Math.PI / 2   // cylinder +Y (radiusTop) → body +Z (back)
    return mesh
  }

  private hinge(x: number, y: number, z: number, surface: THREE.Mesh, offsetZ: number) {
    const h = new THREE.Group()
    h.position.set(x, y, z)
    surface.position.set(0, 0, offsetZ)
    h.add(surface)
    this.root.add(h)
    return h
  }

  private box(w: number, h: number, l: number, m: THREE.Material) { return new THREE.Mesh(new THREE.BoxGeometry(w, h, l), m) }

  private navLights(span: number, y: number, z: number) {
    for (const [x, c] of [[-span, 0xff2020], [span, 0x20ff40]] as const) {
      this.add(new THREE.SphereGeometry(0.09, 8, 8), new THREE.MeshBasicMaterial({ color: c }), x, y, z)
    }
  }

  private buildTrainer(paint: number) {
    this.chaseDistance = 16
    this.cockpitEye.set(0, 0.45, -0.55)
    const white = mat(0xf2f2f2, { metalness: 0.1, roughness: 0.35 })
    const trim = mat(paint, { metalness: 0.1, roughness: 0.4 })
    const dark = mat(0x1f1f1f, { metalness: 0.3, roughness: 0.6 })
    const glass = mat(0x203040, { metalness: 0.8, roughness: 0.05, transparent: true, opacity: 0.45 })

    this.tube(0.62, 0.62, 3.4, white, -0.2)
    this.tube(0.35, 0.62, 0.9, white, -2.35)
    this.tube(0.62, 0.12, 3.8, white, 3.4, 0.15)
    const stripe = this.tube(0.635, 0.635, 3.0, trim, -0.2, -0.1)
    stripe.scale.set(1, 1, 0.12)
    this.add(new THREE.BoxGeometry(1.0, 0.45, 1.3), glass, 0, 0.5, -0.6)

    this.add(new THREE.BoxGeometry(11, 0.14, 1.5), white, 0, 0.92, -0.1)
    for (const x of [-1, 1]) {
      this.add(new THREE.BoxGeometry(0.3, 0.15, 1.5), trim, x * 5.4, 0.92, -0.1)
      const strut = this.add(new THREE.CylinderGeometry(0.04, 0.04, 2.9, 6), white, x * 1.4, 0.15, -0.1)
      strut.rotation.z = x * 1.1
    }
    this.leftAileron = this.hinge(-4.0, 0.92, 0.55, this.box(2.4, 0.06, 0.35, trim), 0.17)
    this.rightAileron = this.hinge(4.0, 0.92, 0.55, this.box(2.4, 0.06, 0.35, trim), 0.17)
    this.flaps = [this.hinge(-1.8, 0.88, 0.55, this.box(2.4, 0.05, 0.35, white), 0.17),
                  this.hinge(1.8, 0.88, 0.55, this.box(2.4, 0.05, 0.35, white), 0.17)]

    this.add(new THREE.BoxGeometry(3.4, 0.08, 0.8), white, 0, 0.25, 5.0)
    this.elevators = [this.hinge(0, 0.25, 5.4, this.box(3.4, 0.06, 0.45, trim), 0.22)]
    this.add(new THREE.BoxGeometry(0.08, 1.4, 1.0), white, 0, 1.0, 5.0)
    this.rudders = [this.hinge(0, 1.0, 5.5, this.box(0.07, 1.4, 0.45, trim), 0.22)]

    const prop = new THREE.Group()
    prop.position.set(0, 0, -2.85)
    prop.add(this.box(1.9, 0.16, 0.05, dark))
    const spinner = new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.35, 16), trim)
    spinner.rotation.x = -Math.PI / 2
    prop.add(spinner)
    this.root.add(prop)
    this.propeller = prop
    const disc = this.add(new THREE.CircleGeometry(0.95, 32), new THREE.MeshBasicMaterial({ color: 0x333333, transparent: true, opacity: 0.18, side: THREE.DoubleSide }), 0, 0, -2.86)
    disc.visible = false
    this.propDisc = disc

    for (const [x, z] of [[0, -1.6], [-1.25, 0.35], [1.25, 0.35]]) {
      const wheel = this.add(new THREE.CylinderGeometry(0.3, 0.3, 0.18, 16), dark, x, -1.0, z)
      wheel.rotation.z = Math.PI / 2
      const leg = this.add(new THREE.CylinderGeometry(0.05, 0.05, 0.9, 6), white, x * 0.7, -0.55, z)
      leg.rotation.z = x * 0.5
    }
    this.navLights(5.56, 0.92, -0.1)
  }

  /** Flat planform: points are (x = right, y = forward); lies in the body XZ plane. */
  private planform(points: [number, number][], thickness: number, m: THREE.Material) {
    const shape = new THREE.Shape(points.map(([x, y]) => new THREE.Vector2(x, y)))
    const geo = new THREE.ExtrudeGeometry(shape, { depth: thickness, bevelEnabled: false })
    geo.translate(0, 0, -thickness / 2)
    const mesh = new THREE.Mesh(geo, m)
    mesh.rotation.x = -Math.PI / 2   // shape +Y → body -Z (forward)
    return mesh
  }

  private buildFighter(paint: number) {
    this.chaseDistance = 30
    this.cockpitEye.set(0, 1.05, -4.6)
    const skin = mat(paint, { metalness: 0.45, roughness: 0.45 })
    const darker = mat(new THREE.Color(paint).multiplyScalar(0.65).getHex(), { metalness: 0.5, roughness: 0.5 })
    const dark = mat(0x1a1a1a, { metalness: 0.6, roughness: 0.4 })
    const glass = mat(0xc8a040, { metalness: 0.9, roughness: 0.05, transparent: true, opacity: 0.45 })
    const flame = new THREE.MeshBasicMaterial({ color: 0xffa040, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false })

    const fus = this.tube(0.85, 0.85, 11.5, skin, 0.6)
    fus.scale.set(1.1, 1, 0.85)
    this.tube(0, 0.8, 4.2, skin, -7.25, 0.05)
    this.tube(0, 0.35, 1.2, darker, -8.75, 0.05)
    const canopy = this.add(new THREE.SphereGeometry(1, 24, 16), glass, 0, 0.75, -4.2)
    canopy.scale.set(0.55, 0.55, 1.9)

    const wing = this.planform([[-0.9, 4.8], [-1.4, 1.0], [-6.1, -1.7], [-6.1, -2.6], [-1.0, -3.4], [1.0, -3.4], [6.1, -2.6], [6.1, -1.7], [1.4, 1.0], [0.9, 4.8]], 0.18, skin)
    wing.position.y = -0.1
    this.root.add(wing)
    this.leftAileron = this.hinge(-4.6, -0.1, 2.25, this.box(2.4, 0.08, 0.55, darker), 0.27)
    this.rightAileron = this.hinge(4.6, -0.1, 2.25, this.box(2.4, 0.08, 0.55, darker), 0.27)
    this.flaps = [this.hinge(-2.2, -0.12, 2.75, this.box(2.0, 0.08, 0.6, darker), 0.3),
                  this.hinge(2.2, -0.12, 2.75, this.box(2.0, 0.08, 0.6, darker), 0.3)]

    for (const x of [-1, 1]) {
      const h = new THREE.Group()
      h.position.set(x * 1.0, -0.05, 6.6)
      h.add(this.planform([[0, 0.9], [x * 2.6, -0.6], [x * 2.6, -1.3], [0, -1.4]], 0.1, skin))
      this.root.add(h)
      this.elevators.push(h)
    }
    for (const x of [-1, 1]) {
      const tail = new THREE.Group()
      tail.position.set(x * 1.3, 0.5, 4.6)
      tail.rotation.z = -x * 0.35
      // Fin in the body YZ plane: shape x = up, y = forward.
      const shape = new THREE.Shape([[0, 1.5], [0, -1.6], [3.0, -1.9], [3.0, -0.9]].map(([a, b]) => new THREE.Vector2(b, a)))
      const geo = new THREE.ExtrudeGeometry(shape, { depth: 0.1, bevelEnabled: false })
      const fin = new THREE.Mesh(geo, skin)
      fin.rotation.y = Math.PI / 2   // shape X → body -Z (forward), shape Y → up
      fin.position.x = 0.05
      tail.add(fin)
      const rh = new THREE.Group()
      rh.position.set(0, 1.0, 1.4)
      const rudder = this.box(0.08, 1.5, 0.5, darker)
      rudder.position.z = 0.25
      rh.add(rudder)
      tail.add(rh)
      this.root.add(tail)
      this.rudders.push(rh)
    }
    for (const x of [-0.55, 0.55]) {
      const n = this.add(new THREE.CylinderGeometry(0.48, 0.48, 1.0, 16), dark, x, -0.1, 7.0)
      n.rotation.x = Math.PI / 2
      const plume = this.add(new THREE.ConeGeometry(0.42, 4.0, 16, 1, true), flame.clone(), x, -0.1, 9.5)
      plume.rotation.x = Math.PI / 2   // cone tip trails aft
      plume.visible = false
      this.afterburners.push(plume)
    }
    const white = mat(0xffffff)
    for (const [x, z] of [[0, -5.5], [-1.6, 0.8], [1.6, 0.8]]) {
      const gear = new THREE.Group()
      gear.position.set(x, -0.4, z)
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 1.3, 6), white)
      leg.position.y = -0.6
      gear.add(leg)
      const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.4, 0.25, 16), dark)
      wheel.rotation.z = Math.PI / 2
      wheel.position.y = -1.2
      gear.add(wheel)
      this.root.add(gear)
      this.gearNodes.push(gear)
    }
    this.navLights(6.1, -0.05, 2.2)
  }
}
