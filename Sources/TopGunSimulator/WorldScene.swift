import SceneKit
import AppKit
import FlightCore
import simd

enum CameraMode: String, CaseIterable, Identifiable {
    case chase = "Chase", cockpit = "Cockpit", orbit = "Orbit", tower = "Tower"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .chase: return "airplane"
        case .cockpit: return "eye"
        case .orbit: return "rotate.3d"
        case .tower: return "building.2"
        }
    }
    var next: CameraMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Builds the 3D world once and moves things around every frame.
final class WorldScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var player: AircraftModel?
    private(set) var bandit: AircraftModel?
    private var gateNodes: [SCNNode] = []
    private var papiLights: [SCNMaterial] = []
    private let tracer = SCNNode()
    private let banditTracer = SCNNode()
    private var smoothedCameraPos: SIMD3<Float>?
    private var explosions = Set<String>()

    var orbitAzimuth: Float = 0.6
    var orbitElevation: Float = 0.25
    var orbitDistanceScale: Float = 1.6

    init() {
        buildSky()
        buildLights()
        buildTerrain()
        buildAirport()
        buildTracers()
        let camera = SCNCamera()
        camera.zNear = 0.25
        camera.zFar = 60_000
        camera.fieldOfView = 65
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: Session wiring

    func load(session: FlightSession) {
        player?.root.removeFromParentNode()
        bandit?.root.removeFromParentNode()
        gateNodes.forEach { $0.removeFromParentNode() }
        gateNodes = []
        explosions.removeAll()
        scene.rootNode.childNodes.filter { $0.name == "explosion" }.forEach { $0.removeFromParentNode() }

        let paint = session.player.spec.kind == .trainer ? NSColor(hex: 0xC8202A) : NSColor(hex: 0x8C98A4)
        let model = AircraftModel(spec: session.player.spec, paint: paint)
        scene.rootNode.addChildNode(model.root)
        player = model
        if let b = session.bandit {
            let m = AircraftModel(spec: b.spec, paint: NSColor(hex: 0x6E2A2A))
            scene.rootNode.addChildNode(m.root)
            bandit = m
        } else {
            bandit = nil
        }
        for gate in session.gates {
            let torus = SCNTorus(ringRadius: CGFloat(gate.radius), pipeRadius: 1.6)
            let m = SCNMaterial()
            m.diffuse.contents = NSColor(hex: 0xFF8C1A)
            m.emission.contents = NSColor(hex: 0xFF8C1A, alpha: 0.8)
            torus.materials = [m]
            let n = SCNNode(geometry: torus)
            n.simdPosition = SIMD3<Float>(gate.center)
            n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(simd_normalize(gate.normal)))
            scene.rootNode.addChildNode(n)
            gateNodes.append(n)
        }
        smoothedCameraPos = nil
    }

    func update(session: FlightSession, camera mode: CameraMode, fov: Double, dt: Double) {
        guard let player else { return }
        let time = session.time
        player.update(state: session.player.state, time: time)
        if let b = session.bandit, let bm = bandit {
            bm.update(state: b.state, time: time)
            if b.state.health <= 0 { explode(at: bm.root.position, key: "bandit") }
        }
        if session.player.state.crashed { explode(at: player.root.position, key: "player") }
        for (i, gate) in session.gates.enumerated() where i < gateNodes.count {
            let color: NSColor
            switch gate.status {
            case .pending: color = NSColor(hex: 0xFF8C1A)
            case .passed: color = NSColor(hex: 0x30D158)
            case .missed: color = NSColor(hex: 0x8E8E93)
            }
            gateNodes[i].geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.8)
            gateNodes[i].geometry?.firstMaterial?.diffuse.contents = color
        }
        updatePAPI(position: session.player.state.position)
        updateTracer(tracer, from: session.player.state, firing: session.firing, time: time)
        if let b = session.bandit { updateTracer(banditTracer, from: b.state, firing: session.banditFiring, time: time) } else { banditTracer.isHidden = true }
        updateCamera(session: session, mode: mode, fov: fov, dt: dt)
    }

    /// Projects a world point to view coordinates (nil if behind the camera).
    func project(_ p: Vec3, in view: SCNView) -> CGPoint? {
        let world = SIMD3<Float>(p)
        let camPos = cameraNode.simdWorldPosition
        let forward = cameraNode.simdWorldFront
        guard simd_dot(world - camPos, forward) > 0 else { return nil }
        let v = view.projectPoint(SCNVector3(world))
        return CGPoint(x: v.x, y: view.bounds.height - v.y)
    }

    // MARK: Camera

    private func updateCamera(session: FlightSession, mode: CameraMode, fov: Double, dt: Double) {
        guard let player else { return }
        let s = session.player.state
        let pos = SIMD3<Float>(s.position)
        let fwd = SIMD3<Float>(s.forward), up = SIMD3<Float>(s.up)
        let camera = cameraNode.camera!
        camera.fieldOfView = CGFloat(fov)
        let dist = Float(player.chaseDistance)

        switch mode {
        case .cockpit:
            let eye = player.root.simdConvertPosition(SIMD3<Float>(Float(player.cockpitEye.x), Float(player.cockpitEye.y), Float(player.cockpitEye.z)), to: nil)
            cameraNode.simdPosition = eye
            cameraNode.simdOrientation = player.root.simdOrientation
            camera.zNear = 0.1
            smoothedCameraPos = nil
            return
        case .chase:
            // Sits behind and above, following the flight path with a little lag.
            let level = simd_normalize(SIMD3<Float>(fwd.x, 0, fwd.z) + SIMD3<Float>(0, fwd.y, 0) * 0.8)
            let target = pos - level * dist + SIMD3<Float>(0, 1, 0) * dist * 0.22 + up * dist * 0.08
            let k = Float(1 - exp(-dt * 8))
            var cam = smoothedCameraPos ?? target
            cam += (target - cam) * k
            smoothedCameraPos = cam
            cameraNode.simdPosition = cam
            cameraNode.simdLook(at: pos + fwd * dist * 0.6, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
        case .orbit:
            let r = dist * orbitDistanceScale
            let offset = SIMD3<Float>(sin(orbitAzimuth) * cos(orbitElevation), sin(orbitElevation), cos(orbitAzimuth) * cos(orbitElevation)) * r
            cameraNode.simdPosition = pos + offset
            cameraNode.simdLook(at: pos, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            smoothedCameraPos = nil
        case .tower:
            let tower = SIMD3<Float>(120, 35, 150)
            cameraNode.simdPosition = tower
            cameraNode.simdLook(at: pos, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            let range = simd_length(pos - tower)
            camera.fieldOfView = CGFloat(clamp(Double(2 * atan(40 / range)).degrees, 4, fov))
            smoothedCameraPos = nil
        }
        // Keep the camera above the terrain.
        let c = cameraNode.simdPosition
        let ground = Float(Terrain.height(x: Double(c.x), z: Double(c.z))) + 1.5
        if c.y < ground { cameraNode.simdPosition.y = ground }
        camera.zNear = 0.5
    }

    // MARK: Effects

    private func buildTracers() {
        for (node, color) in [(tracer, NSColor(hex: 0xFFE070)), (banditTracer, NSColor(hex: 0xFF5050))] {
            let g = SCNCylinder(radius: 0.25, height: 900)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = color
            m.emission.contents = color
            m.blendMode = .add
            g.materials = [m]
            let inner = SCNNode(geometry: g)
            inner.eulerAngles.x = .pi / 2
            inner.position = SCNVector3(0, 0, -460)
            node.addChildNode(inner)
            node.isHidden = true
            scene.rootNode.addChildNode(node)
        }
    }

    private func updateTracer(_ node: SCNNode, from s: AircraftState, firing: Bool, time: Double) {
        node.isHidden = !firing || Int(time * 30) % 2 == 0
        guard firing else { return }
        node.simdPosition = SIMD3<Float>(s.position + s.forward * 6 + s.up * 0.5)
        node.simdOrientation = simd_quatf(ix: Float(s.orientation.imag.x), iy: Float(s.orientation.imag.y), iz: Float(s.orientation.imag.z), r: Float(s.orientation.real))
    }

    private func explode(at position: SCNVector3, key: String) {
        guard !explosions.contains(key) else { return }
        explosions.insert(key)
        let fire = SCNParticleSystem()
        fire.birthRate = 600
        fire.emissionDuration = 0.6
        fire.loops = false
        fire.particleLifeSpan = 1.6
        fire.particleVelocity = 40
        fire.particleVelocityVariation = 30
        fire.spreadingAngle = 180
        fire.particleSize = 6
        fire.particleSizeVariation = 3
        fire.particleColor = NSColor(hex: 0xFF8A20)
        fire.particleImage = Self.softDot
        fire.blendMode = .additive
        fire.particleColorVariation = SCNVector4(0.05, 0.2, 0.2, 0)
        let smoke = SCNParticleSystem()
        smoke.birthRate = 40
        smoke.particleLifeSpan = 6
        smoke.particleVelocity = 8
        smoke.spreadingAngle = 30
        smoke.emittingDirection = SCNVector3(0, 1, 0)
        smoke.particleSize = 14
        smoke.particleColor = NSColor(white: 0.15, alpha: 0.6)
        smoke.particleImage = Self.softDot
        smoke.blendMode = .alpha
        smoke.acceleration = SCNVector3(0, 4, 0)
        let node = SCNNode()
        node.name = "explosion"
        node.position = position
        node.addParticleSystem(fire)
        node.addParticleSystem(smoke)
        scene.rootNode.addChildNode(node)
    }

    static let softDot: NSImage = {
        let size = 64
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let g = NSGradient(colors: [NSColor.white, NSColor.white.withAlphaComponent(0)])
            g?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }()

    // MARK: World building

    private func buildSky() {
        let horizon = NSColor(hex: 0xD6E8F7), zenith = NSColor(hex: 0x4A8FE0), ground = NSColor(hex: 0x8FA88A)
        let w = 1024, h = 512
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            let top = NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2)
            NSGradient(colors: [horizon, zenith], atLocations: [0, 1], colorSpace: .sRGB)?.draw(in: top, angle: 90)
            let bottom = NSRect(x: 0, y: 0, width: rect.width, height: rect.height / 2)
            NSGradient(colors: [ground, horizon])?.draw(in: bottom, angle: 90)
            return true
        }
        scene.background.contents = img
        scene.fogColor = horizon
        scene.fogStartDistance = 7000
        scene.fogEndDistance = 32_000
        scene.fogDensityExponent = 1.4
    }

    private func buildLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1700
        sun.color = NSColor(hex: 0xFFF4E0)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, 0.6, 0)
        scene.rootNode.addChildNode(sunNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 550
        ambient.color = NSColor(hex: 0xB8CCE6)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func buildTerrain() {
        let minX = -22_000.0, maxX = 22_000.0, minZ = -32_000.0, maxZ = 12_000.0
        let step = 125.0
        let nx = Int((maxX - minX) / step) + 1, nz = Int((maxZ - minZ) / step) + 1
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        vertices.reserveCapacity(nx * nz)
        for j in 0..<nz {
            for i in 0..<nx {
                let x = minX + Double(i) * step, z = minZ + Double(j) * step
                let h = Terrain.height(x: x, z: z)
                vertices.append(SCNVector3(x, h - 0.6, z))
                let n = Terrain.normal(x: x, z: z)
                normals.append(SCNVector3(n.x, n.y, n.z))
                colors.append(Self.groundColor(height: h, slope: 1 - n.y, x: x, z: z))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((nx - 1) * (nz - 1) * 6)
        for j in 0..<(nz - 1) {
            for i in 0..<(nx - 1) {
                let a = UInt32(j * nx + i), b = a + 1, c = a + UInt32(nx), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                            dataOffset: 0, dataStride: 16)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = NSColor.white
        geometry.materials = [m]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        // A big flat apron beyond the mesh so the horizon never shows a hole.
        let plane = SCNPlane(width: 400_000, height: 400_000)
        let pm = SCNMaterial()
        pm.lightingModel = .lambert
        pm.diffuse.contents = NSColor(hex: 0x6E8F55)
        plane.materials = [pm]
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        planeNode.position = SCNVector3(0, -3, -10_000)
        scene.rootNode.addChildNode(planeNode)
    }

    static func groundColor(height h: Double, slope: Double, x: Double, z: Double) -> SIMD4<Float> {
        let noise = Float(0.04 * sin(x * 0.013) * cos(z * 0.011) + 0.03 * sin(x * 0.051 + z * 0.037))
        var c: SIMD3<Float>
        if h < 2 {
            c = SIMD3(0.36, 0.52, 0.27)                          // airport grass
        } else if h < 250 {
            c = simd_mix(SIMD3(0.38, 0.54, 0.28), SIMD3(0.28, 0.42, 0.22), SIMD3(repeating: Float(h / 250)))
        } else if h < 700 {
            c = simd_mix(SIMD3(0.28, 0.42, 0.22), SIMD3(0.48, 0.42, 0.33), SIMD3(repeating: Float((h - 250) / 450)))
        } else {
            c = simd_mix(SIMD3(0.48, 0.42, 0.33), SIMD3(0.92, 0.93, 0.96), SIMD3(repeating: Float(smoothstep(900, 1150, h))))
        }
        if slope > 0.25 { c = simd_mix(c, SIMD3(0.45, 0.4, 0.34), SIMD3(repeating: Float(min(1, (slope - 0.25) * 2.5)))) }
        c += SIMD3(repeating: noise)
        return SIMD4(c, 1)
    }

    private func flatMaterial(_ color: NSColor, emission: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = emission ? .constant : .lambert
        m.diffuse.contents = color
        if emission { m.emission.contents = color }
        return m
    }

    private func buildAirport() {
        let airport = SCNNode()
        let len = CGFloat(Terrain.runwayLength), width = CGFloat(Terrain.runwayWidth)
        let runway = SCNBox(width: width, height: 0.4, length: len, chamferRadius: 0)
        runway.materials = [flatMaterial(NSColor(hex: 0x3A3D42))]
        let runwayNode = SCNNode(geometry: runway)
        runwayNode.position = SCNVector3(0, -0.2, 0)
        airport.addChildNode(runwayNode)

        let white = flatMaterial(NSColor(white: 0.93, alpha: 1))
        func stripe(x: CGFloat, z: CGFloat, w: CGFloat, l: CGFloat) {
            let b = SCNBox(width: w, height: 0.02, length: l, chamferRadius: 0)
            b.materials = [white]
            let n = SCNNode(geometry: b)
            n.position = SCNVector3(x, 0.01, z)
            airport.addChildNode(n)
        }
        // Centreline dashes
        var z = -len / 2 + 60
        while z < len / 2 - 60 { stripe(x: 0, z: z, w: 0.9, l: 30); z += 60 }
        // Threshold piano keys and edge lines at both ends
        for end: CGFloat in [-1, 1] {
            for i in 0..<8 {
                let x = -width / 2 + 4 + CGFloat(i) * 5.2 + (i >= 4 ? 2 : 0)
                stripe(x: x, z: end * (len / 2 - 25), w: 1.8, l: 30)
            }
            for i in 0..<3 { stripe(x: -10, z: end * (len / 2 - 330 - CGFloat(i) * 12), w: 3, l: 8); stripe(x: 10, z: end * (len / 2 - 330 - CGFloat(i) * 12), w: 3, l: 8) }
        }
        stripe(x: -width / 2 + 1, z: 0, w: 0.9, l: len)
        stripe(x: width / 2 - 1, z: 0, w: 0.9, l: len)

        // Runway numbers
        for (text, zPos, rot) in [("36", len / 2 - 95, CGFloat.pi), ("18", -len / 2 + 95, CGFloat(0))] {
            let t = SCNText(string: text, extrusionDepth: 0.02)
            t.font = NSFont.systemFont(ofSize: 18, weight: .bold)
            t.flatness = 0.2
            t.materials = [white]
            let n = SCNNode(geometry: t)
            let (minB, maxB) = n.boundingBox
            n.pivot = SCNMatrix4MakeTranslation((maxB.x + minB.x) / 2, (maxB.y + minB.y) / 2, 0)
            n.eulerAngles = SCNVector3(-CGFloat.pi / 2, rot, 0)
            n.position = SCNVector3(0, 0.03, zPos)
            airport.addChildNode(n)
        }

        // Edge lights
        let lightMat = flatMaterial(NSColor(hex: 0xFFF3C0), emission: true)
        let lightGeo = SCNSphere(radius: 0.35)
        lightGeo.materials = [lightMat]
        z = -len / 2
        while z <= len / 2 {
            for x in [-width / 2 - 2, width / 2 + 2] {
                let n = SCNNode(geometry: lightGeo)
                n.position = SCNVector3(x, 0.3, z)
                airport.addChildNode(n)
            }
            z += 60
        }
        // Approach lights south of runway 36
        for i in 1...10 {
            let zz = len / 2 + CGFloat(i) * 30
            for dx: CGFloat in [-3, 0, 3] {
                let n = SCNNode(geometry: lightGeo)
                n.position = SCNVector3(dx, 0.6, zz)
                airport.addChildNode(n)
            }
        }
        // PAPI: four lights left of the touchdown zone. White = above that light's angle, red = below.
        for i in 0..<4 {
            let m = flatMaterial(.white, emission: true)
            let g = SCNBox(width: 1.6, height: 1.0, length: 0.6, chamferRadius: 0.2)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(-width / 2 - 15 - CGFloat(i) * 9, 0.6, len / 2 - 300)
            airport.addChildNode(n)
            papiLights.append(m)
        }

        // Buildings for scale
        let concrete = flatMaterial(NSColor(hex: 0xC8C4BC)), roof = flatMaterial(NSColor(hex: 0x5E6B78))
        let glass = flatMaterial(NSColor(hex: 0x2A4058))
        let tower = SCNBox(width: 6, height: 28, length: 6, chamferRadius: 0)
        tower.materials = [concrete]
        let towerNode = SCNNode(geometry: tower)
        towerNode.position = SCNVector3(120, 14, 150)
        airport.addChildNode(towerNode)
        let cab = SCNBox(width: 10, height: 5, length: 10, chamferRadius: 0.5)
        cab.materials = [glass]
        let cabNode = SCNNode(geometry: cab)
        cabNode.position = SCNVector3(120, 30, 150)
        airport.addChildNode(cabNode)
        for i in 0..<4 {
            let hangar = SCNBox(width: 40, height: 14, length: 36, chamferRadius: 0)
            hangar.materials = [roof, concrete, roof, concrete, roof, concrete]
            let h = SCNNode(geometry: hangar)
            h.position = SCNVector3(170, 7, CGFloat(-200 + i * 55))
            airport.addChildNode(h)
        }
        let apron = SCNBox(width: 110, height: 0.3, length: 300, chamferRadius: 0)
        apron.materials = [flatMaterial(NSColor(hex: 0x55585D))]
        let apronNode = SCNNode(geometry: apron)
        apronNode.position = SCNVector3(110, -0.15, -100)
        airport.addChildNode(apronNode)
        scene.rootNode.addChildNode(airport)

        buildTrees()
    }

    private func buildTrees() {
        var rng = SeededRandom(seed: 7)
        let trees = SCNNode()
        let leaf = flatMaterial(NSColor(hex: 0x2F5A2A)), trunk = flatMaterial(NSColor(hex: 0x5A4030))
        let cone = SCNCone(topRadius: 0, bottomRadius: 4, height: 12)
        cone.materials = [leaf]
        let stem = SCNCylinder(radius: 0.6, height: 3)
        stem.materials = [trunk]
        var placed = 0
        while placed < 700 {
            let x = rng.signedUnit() * 9000, z = rng.signedUnit() * 9000 - 2000
            if abs(x) < 250 && abs(z) < 1700 { continue }       // keep runway clear
            if x > 60 && x < 260 && z > -300 && z < 220 { continue }
            let h = Terrain.height(x: x, z: z)
            let t = SCNNode()
            let c = SCNNode(geometry: cone); c.position = SCNVector3(0, 9, 0)
            let s = SCNNode(geometry: stem); s.position = SCNVector3(0, 1.5, 0)
            t.addChildNode(c); t.addChildNode(s)
            let scale = 0.7 + 0.6 * (rng.signedUnit() + 1) / 2
            t.scale = SCNVector3(scale, scale, scale)
            t.position = SCNVector3(x, h - 0.6, z)
            trees.addChildNode(t)
            placed += 1
        }
        scene.rootNode.addChildNode(trees.flattenedClone())
    }

    private func updatePAPI(position p: Vec3) {
        let lightZ = Terrain.runwaySouthEnd - 300
        let dz = p.z - lightZ
        guard dz > 0 else { papiLights.forEach { $0.emission.contents = NSColor.white; $0.diffuse.contents = NSColor.white }; return }
        let angle = atan2(p.y, dz).degrees
        // Light i (outboard = 0) shows white when above its threshold: 3.5°, 3.17°, 2.83°, 2.5°.
        let thresholds = [3.5, 3.17, 2.83, 2.5]
        for (i, m) in papiLights.enumerated() {
            let c: NSColor = angle > thresholds[i] ? .white : NSColor(hex: 0xFF2020)
            m.emission.contents = c
            m.diffuse.contents = c
        }
    }
}

extension SIMD3 where Scalar == Float {
    init(_ v: Vec3) { self.init(Float(v.x), Float(v.y), Float(v.z)) }
}
