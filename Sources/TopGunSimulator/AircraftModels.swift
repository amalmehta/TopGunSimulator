import SceneKit
import AppKit
import FlightCore

/// Nodes the renderer animates every frame.
final class AircraftModel {
    let root = SCNNode()
    var leftAileron = SCNNode(), rightAileron = SCNNode()
    var elevators: [SCNNode] = []
    var rudders: [SCNNode] = []
    var flaps: [SCNNode] = []
    var propeller: SCNNode?
    var propDisc: SCNNode?
    var afterburners: [SCNNode] = []
    var gearNodes: [SCNNode] = []
    var cockpitEye = SCNVector3Zero
    var chaseDistance: CGFloat = 18
    let spec: AircraftSpec

    init(spec: AircraftSpec, paint: NSColor) {
        self.spec = spec
        switch spec.kind {
        case .trainer: buildTrainer(paint: paint)
        case .fighter: buildFighter(paint: paint)
        }
    }

    /// Mirrors the simulation state onto the model.
    func update(state: AircraftState, time: TimeInterval) {
        root.simdPosition = SIMD3<Float>(state.position)
        root.simdOrientation = simd_quatf(ix: Float(state.orientation.imag.x), iy: Float(state.orientation.imag.y),
                                         iz: Float(state.orientation.imag.z), r: Float(state.orientation.real))
        let s = state.surfaces
        let aileronMax: CGFloat = 0.35, elevatorMax: CGFloat = 0.4, rudderMax: CGFloat = 0.45
        // Hinge nodes rotate about their local X (ailerons/elevator) or Y (rudder) axis; positive = trailing edge down/right.
        rightAileron.eulerAngles.x = -CGFloat(s.aileron) * aileronMax
        leftAileron.eulerAngles.x = CGFloat(s.aileron) * aileronMax
        for e in elevators { e.eulerAngles.x = -CGFloat(s.elevator) * elevatorMax }
        for r in rudders { r.eulerAngles.y = CGFloat(s.rudder) * rudderMax }
        for f in flaps { f.eulerAngles.x = CGFloat(state.flaps) * 0.6 }
        if let prop = propeller {
            let rpm = 0.15 + state.engine * 0.85
            prop.eulerAngles.z = CGFloat((time * 40 * rpm).truncatingRemainder(dividingBy: .pi * 2))
            prop.opacity = state.engine > 0.3 ? 0.25 : 1
            propDisc?.opacity = CGFloat(state.engine > 0.3 ? 0.18 : 0)
        }
        let burner = state.engine > 0.95 ? CGFloat(0.6 + 0.4 * sin(time * 50)) : 0
        for ab in afterburners { ab.opacity = burner }
        for g in gearNodes { g.isHidden = state.gear < 0.5; g.scale = SCNVector3(1, CGFloat(max(state.gear, 0.01)), 1) }
    }

    // MARK: Builders

    private func material(_ color: NSColor, metal: CGFloat = 0.2, rough: CGFloat = 0.5, emission: NSColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let emission { m.emission.contents = emission }
        return m
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, chamfer: CGFloat = 0.02) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// A cylinder along the body's fore-aft (Z) axis.
    private func tube(radius: CGFloat, length: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: length)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.eulerAngles.x = .pi / 2
        return n
    }

    /// A hinge node: rotate it to deflect the surface built behind it (+Z).
    private func hinge(at p: SCNVector3, surface: SCNNode, offsetZ: CGFloat) -> SCNNode {
        let h = SCNNode()
        h.position = p
        surface.position = SCNVector3(0, 0, offsetZ)
        h.addChildNode(surface)
        root.addChildNode(h)
        return h
    }

    private func navLights(span: CGFloat, y: CGFloat, z: CGFloat) {
        for (x, color) in [(-span, NSColor.red), (span, NSColor.green)] {
            let s = SCNSphere(radius: 0.09)
            s.materials = [material(color, emission: color)]
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(x, y, z)
            root.addChildNode(n)
        }
    }

    private func buildTrainer(paint: NSColor) {
        chaseDistance = 16
        cockpitEye = SCNVector3(0, 0.45, -0.55)
        let white = material(NSColor(white: 0.95, alpha: 1), metal: 0.1, rough: 0.35)
        let trim = material(paint, metal: 0.1, rough: 0.4)
        let dark = material(NSColor(white: 0.12, alpha: 1), metal: 0.3, rough: 0.6)
        let glass = material(NSColor(hex: 0x203040, alpha: 0.55), metal: 0.8, rough: 0.05)
        glass.transparency = 0.6

        let fuselage = tube(radius: 0.62, length: 3.4, white)
        fuselage.position = SCNVector3(0, 0, -0.2)
        root.addChildNode(fuselage)
        let cowl = SCNCone(topRadius: 0.62, bottomRadius: 0.35, height: 0.9)
        cowl.materials = [white]
        let cowlNode = SCNNode(geometry: cowl)
        cowlNode.eulerAngles.x = -.pi / 2
        cowlNode.position = SCNVector3(0, 0, -2.35)
        root.addChildNode(cowlNode)
        let tailcone = SCNCone(topRadius: 0.62, bottomRadius: 0.12, height: 3.8)
        tailcone.materials = [white]
        let tailNode = SCNNode(geometry: tailcone)
        tailNode.eulerAngles.x = .pi / 2
        tailNode.position = SCNVector3(0, 0.15, 3.4)
        root.addChildNode(tailNode)
        let stripe = tube(radius: 0.635, length: 3.0, trim)
        stripe.scale = SCNVector3(1, 1, 0.12)
        stripe.position = SCNVector3(0, -0.1, -0.2)
        root.addChildNode(stripe)
        let windshield = box(1.0, 0.45, 1.3, glass, chamfer: 0.15)
        windshield.position = SCNVector3(0, 0.5, -0.6)
        root.addChildNode(windshield)

        // High wing with struts
        let wing = box(11, 0.14, 1.5, white, chamfer: 0.05)
        wing.position = SCNVector3(0, 0.92, -0.1)
        root.addChildNode(wing)
        for x: CGFloat in [-1, 1] {
            let tip = box(0.3, 0.15, 1.5, trim)
            tip.position = SCNVector3(x * 5.4, 0.92, -0.1)
            root.addChildNode(tip)
            let strut = SCNCylinder(radius: 0.04, height: 2.9)
            strut.materials = [white]
            let s = SCNNode(geometry: strut)
            s.position = SCNVector3(x * 1.4, 0.15, -0.1)
            s.eulerAngles.z = x * 1.1
            root.addChildNode(s)
        }
        leftAileron = hinge(at: SCNVector3(-4.0, 0.92, 0.55), surface: box(2.4, 0.06, 0.35, trim), offsetZ: 0.17)
        rightAileron = hinge(at: SCNVector3(4.0, 0.92, 0.55), surface: box(2.4, 0.06, 0.35, trim), offsetZ: 0.17)
        flaps = [hinge(at: SCNVector3(-1.8, 0.88, 0.55), surface: box(2.4, 0.05, 0.35, white), offsetZ: 0.17),
                 hinge(at: SCNVector3(1.8, 0.88, 0.55), surface: box(2.4, 0.05, 0.35, white), offsetZ: 0.17)]

        // Tail
        let hstab = box(3.4, 0.08, 0.8, white)
        hstab.position = SCNVector3(0, 0.25, 5.0)
        root.addChildNode(hstab)
        elevators = [hinge(at: SCNVector3(0, 0.25, 5.4), surface: box(3.4, 0.06, 0.45, trim), offsetZ: 0.22)]
        let fin = box(0.08, 1.4, 1.0, white)
        fin.position = SCNVector3(0, 1.0, 5.0)
        root.addChildNode(fin)
        rudders = [hinge(at: SCNVector3(0, 1.0, 5.5), surface: box(0.07, 1.4, 0.45, trim), offsetZ: 0.22)]

        // Propeller
        let prop = SCNNode()
        prop.position = SCNVector3(0, 0, -2.85)
        let blade = box(1.9, 0.16, 0.05, dark)
        prop.addChildNode(blade)
        let spinner = SCNCone(topRadius: 0, bottomRadius: 0.2, height: 0.35)
        spinner.materials = [trim]
        let spinnerNode = SCNNode(geometry: spinner)
        spinnerNode.eulerAngles.x = -.pi / 2
        prop.addChildNode(spinnerNode)
        root.addChildNode(prop)
        propeller = prop
        let disc = SCNCylinder(radius: 0.95, height: 0.01)
        disc.materials = [material(NSColor(white: 0.2, alpha: 1))]
        let discNode = SCNNode(geometry: disc)
        discNode.eulerAngles.x = .pi / 2
        discNode.position = SCNVector3(0, 0, -2.86)
        discNode.opacity = 0
        root.addChildNode(discNode)
        propDisc = discNode

        // Fixed tricycle gear
        for p in [SCNVector3(0, -1.0, -1.6), SCNVector3(-1.25, -1.0, 0.35), SCNVector3(1.25, -1.0, 0.35)] {
            let wheel = SCNCylinder(radius: 0.3, height: 0.18)
            wheel.materials = [dark]
            let w = SCNNode(geometry: wheel)
            w.eulerAngles.z = .pi / 2
            w.position = p
            root.addChildNode(w)
            let leg = SCNCylinder(radius: 0.05, height: 0.9)
            leg.materials = [white]
            let l = SCNNode(geometry: leg)
            l.position = SCNVector3(p.x * 0.7, -0.55, p.z)
            l.eulerAngles.z = p.x * 0.5
            root.addChildNode(l)
        }
        navLights(span: 5.56, y: 0.92, z: -0.1)
    }

    /// Flat planform shape: points are (x = right, y = forward) in metres; returns a node lying in the body XZ plane.
    private func planform(_ points: [CGPoint], thickness: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.close()
        path.flatness = 0.05
        let shape = SCNShape(path: path, extrusionDepth: thickness)
        shape.materials = [m]
        let n = SCNNode(geometry: shape)
        n.eulerAngles.x = -.pi / 2
        return n
    }

    private func buildFighter(paint: NSColor) {
        chaseDistance = 30
        cockpitEye = SCNVector3(0, 1.05, -4.6)
        let skin = material(paint, metal: 0.45, rough: 0.45)
        let darker = material(paint.blended(withFraction: 0.35, of: .black) ?? paint, metal: 0.5, rough: 0.5)
        let dark = material(NSColor(white: 0.1, alpha: 1), metal: 0.6, rough: 0.4)
        let glass = material(NSColor(hex: 0xC8A040, alpha: 0.5), metal: 0.9, rough: 0.05)
        glass.transparency = 0.45
        let flame = material(NSColor(hex: 0xFF9030), emission: NSColor(hex: 0xFFB050))
        flame.lightingModel = .constant
        flame.blendMode = .add

        let fuselage = tube(radius: 0.85, length: 11.5, skin)
        fuselage.position = SCNVector3(0, 0, 0.6)
        fuselage.scale = SCNVector3(1.1, 1, 0.85)
        root.addChildNode(fuselage)
        let nose = SCNCone(topRadius: 0, bottomRadius: 0.8, height: 4.2)
        nose.materials = [skin]
        let noseNode = SCNNode(geometry: nose)
        noseNode.eulerAngles.x = -.pi / 2
        noseNode.position = SCNVector3(0, 0.05, -7.25)
        root.addChildNode(noseNode)
        let radome = SCNCone(topRadius: 0, bottomRadius: 0.35, height: 1.2)
        radome.materials = [darker]
        let radomeNode = SCNNode(geometry: radome)
        radomeNode.eulerAngles.x = -.pi / 2
        radomeNode.position = SCNVector3(0, 0.05, -8.75)
        root.addChildNode(radomeNode)
        let canopy = SCNSphere(radius: 1)
        canopy.materials = [glass]
        let canopyNode = SCNNode(geometry: canopy)
        canopyNode.scale = SCNVector3(0.55, 0.55, 1.9)
        canopyNode.position = SCNVector3(0, 0.75, -4.2)
        root.addChildNode(canopyNode)

        // Wings with leading-edge extensions
        let wing = planform([CGPoint(x: -0.9, y: 4.8), CGPoint(x: -1.4, y: 1.0), CGPoint(x: -6.1, y: -1.7), CGPoint(x: -6.1, y: -2.6),
                             CGPoint(x: -1.0, y: -3.4), CGPoint(x: 1.0, y: -3.4), CGPoint(x: 6.1, y: -2.6), CGPoint(x: 6.1, y: -1.7),
                             CGPoint(x: 1.4, y: 1.0), CGPoint(x: 0.9, y: 4.8)], thickness: 0.18, skin)
        wing.position = SCNVector3(0, -0.1, 0)
        root.addChildNode(wing)
        leftAileron = hinge(at: SCNVector3(-4.6, -0.1, 2.25), surface: box(2.4, 0.08, 0.55, darker), offsetZ: 0.27)
        rightAileron = hinge(at: SCNVector3(4.6, -0.1, 2.25), surface: box(2.4, 0.08, 0.55, darker), offsetZ: 0.27)
        flaps = [hinge(at: SCNVector3(-2.2, -0.12, 2.75), surface: box(2.0, 0.08, 0.6, darker), offsetZ: 0.3),
                 hinge(at: SCNVector3(2.2, -0.12, 2.75), surface: box(2.0, 0.08, 0.6, darker), offsetZ: 0.3)]

        // All-moving stabilators
        for x: CGFloat in [-1, 1] {
            let stab = planform([CGPoint(x: 0, y: 0.9), CGPoint(x: x * 2.6, y: -0.6), CGPoint(x: x * 2.6, y: -1.3), CGPoint(x: 0, y: -1.4)], thickness: 0.1, skin)
            let h = SCNNode()
            h.position = SCNVector3(x * 1.0, -0.05, 6.6)
            h.addChildNode(stab)
            root.addChildNode(h)
            elevators.append(h)
        }
        // Twin canted tails
        for x: CGFloat in [-1, 1] {
            let tail = SCNNode()
            tail.position = SCNVector3(x * 1.3, 0.5, 4.6)
            tail.eulerAngles.z = -x * 0.35
            let fin = planform([CGPoint(x: 0, y: 1.5), CGPoint(x: 0, y: -1.6), CGPoint(x: 3.0, y: -1.9), CGPoint(x: 3.0, y: -0.9)], thickness: 0.1, skin)
            fin.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, CGFloat.pi / 2)
            tail.addChildNode(fin)
            let rudderHinge = SCNNode()
            rudderHinge.position = SCNVector3(0, 1.0, 1.4)
            let rudder = box(0.08, 1.5, 0.5, darker)
            rudder.position = SCNVector3(0, 0, 0.25)
            rudderHinge.addChildNode(rudder)
            tail.addChildNode(rudderHinge)
            root.addChildNode(tail)
            rudders.append(rudderHinge)
        }
        // Engines and afterburners
        for x: CGFloat in [-0.55, 0.55] {
            let nozzle = SCNCylinder(radius: 0.48, height: 1.0)
            nozzle.materials = [dark]
            let n = SCNNode(geometry: nozzle)
            n.eulerAngles.x = .pi / 2
            n.position = SCNVector3(x, -0.1, 7.0)
            root.addChildNode(n)
            let plume = SCNCone(topRadius: 0.42, bottomRadius: 0.05, height: 4.0)
            plume.materials = [flame]
            let p = SCNNode(geometry: plume)
            p.eulerAngles.x = .pi / 2
            p.position = SCNVector3(x, -0.1, 9.5)
            p.opacity = 0
            root.addChildNode(p)
            afterburners.append(p)
        }
        // Retractable gear
        for p in [SCNVector3(0, -1.6, -5.5), SCNVector3(-1.6, -1.6, 0.8), SCNVector3(1.6, -1.6, 0.8)] {
            let gear = SCNNode()
            gear.position = SCNVector3(p.x, -0.4, p.z)
            let leg = SCNCylinder(radius: 0.08, height: 1.3)
            leg.materials = [material(.white)]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -0.6, 0)
            gear.addChildNode(legNode)
            let wheel = SCNCylinder(radius: 0.4, height: 0.25)
            wheel.materials = [dark]
            let w = SCNNode(geometry: wheel)
            w.eulerAngles.z = .pi / 2
            w.position = SCNVector3(0, -1.2, 0)
            gear.addChildNode(w)
            root.addChildNode(gear)
            gearNodes.append(gear)
        }
        navLights(span: 6.1, y: -0.05, z: 2.2)
    }
}
