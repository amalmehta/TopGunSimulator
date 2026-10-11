# Top Gun Simulator: System Design

## Architecture

Two Swift targets. `FlightCore` is pure simulation: no UI, fully unit-tested. `TopGunSimulator` is the SwiftUI + SceneKit Mac app that drives and displays it.

```mermaid
flowchart TB
    subgraph App["TopGunSimulator (SwiftUI + SceneKit)"]
        Input[InputManager<br/>keyboard · GameController]
        Ctrl[SimulationController<br/>120 Hz timer, events, snapshots]
        World[WorldScene<br/>terrain · airport · models · cameras]
        UI[HUD · InstrumentPanel · Sidebar<br/>Map · Profile · Lesson · Instructor]
        Prefs[(UserDefaults<br/>settings · lesson progress)]
        FB[(feedback.jsonl)]
    end
    subgraph Core["FlightCore (pure Swift)"]
        Session[FlightSession]
        Aircraft[Aircraft<br/>6-DOF flight model]
        Spec[AircraftSpec<br/>trainer · fighter]
        Env[Atmosphere · Terrain · Wind]
        Lessons[LessonCatalog · LessonProgress]
        Instr[Instructor]
        Combat[BanditAI · guns · gates]
    end
    Input --> Ctrl
    Prefs --> Ctrl
    Ctrl -->|advance(by:)| Session
    Session --> Aircraft --> Spec
    Aircraft --> Env
    Session --> Lessons
    Session --> Instr
    Session --> Combat
    Ctrl -->|state each frame| World
    Ctrl -->|FrameSnapshot ~30 Hz| UI
    UI --> FB
```

## Components

| Component | Job |
|---|---|
| `Aircraft` (FlightModel.swift) | Rigid-body 6-DOF physics: aero forces and moments from stability derivatives, a lift curve with stall break and flat-plate post-stall, induced drag with ground effect, prop/jet thrust with spool-up, propeller turning tendency, spring-damper landing gear with steering, brakes and friction, crash and touchdown detection. Also the control laws: direct linkage plus optional auto-rudder (trainer), or fly-by-wire with pitch damper, g- and alpha-limiters and roll-rate command (fighter). |
| `AircraftSpec` | Data for the Cessna-172-like trainer and F/A-18-like fighter: mass, inertia, geometry, aero derivatives, thrust, gear geometry, reference speeds. |
| `Atmosphere`, `Terrain`, `WindModel` | ISA density; an analytic height field (flat airport and approach corridor, hills, a northern range cut by a winding canyon); steady wind plus filtered-noise turbulence. |
| `FlightSession` | One flight: fixed 240 Hz stepping, player and bandit, gates, guns, trails, the event queue, and the lesson and instructor. |
| `LessonCatalog` / `LessonProgress` | 11 lessons. Each step is a check closure that must hold for N seconds, an optional fail closure and a live progress readout. |
| `Instructor` | Turns telemetry into prioritised hints, each with a "why" (stall, sink rate, slip, over-g, trim, rotate…). |
| `BanditAI` | Steers a second `Aircraft` with the same physics: lead pursuit, roll the target into the lift vector, terrain avoidance, fires when in its gun cone. |
| `SimulationController` | Main-thread loop: samples input, advances the session, turns events into toasts and results, pushes state to SceneKit every tick and a `FrameSnapshot` to SwiftUI at ~30 Hz. |
| `WorldScene` / `AircraftModels` | Builds the terrain mesh (vertex-coloured), runway with markings, lights and live PAPI, buildings, trees and gates. Aircraft are built from primitives with hinged ailerons, elevator, rudder and flaps that deflect, plus prop and afterburner. Runs chase, cockpit, orbit and tower cameras, tracers and explosions. |
| HUD / instruments / sidebar | Canvas-drawn HUD (pitch ladder and flight-path marker in the cockpit), six-pack, stick-vs-surface readout, moving map, side profile with glidepath, lesson and instructor panels. |
| Settings / Feedback | Settings window (⌘,) backed by `UserDefaults`; feedback appended to a local JSON-lines file. |

## Main flows

1. **Frame:** a 120 Hz timer → `InputManager.sample` → `FlightSession.advance(by: dt)` runs `floor(dt × 240)` physics steps → telemetry, instructor and lesson update → events drained (toasts, pass/fail, crash) → `WorldScene.update` moves nodes and cameras → every ~33 ms a `FrameSnapshot` is published to SwiftUI.
2. **Lesson:** `SessionMode.lesson` places the aircraft from `LessonStart`. Each frame the current step's `check` runs against telemetry plus mission context (gates, bandit range, touchdown); holding it for `hold` seconds advances the step. A `fail` closure or a crash ends the lesson. Passing records the lesson id in `UserDefaults`.
3. **Physics step:** air-relative velocity in body axes → α, β, q̄ → control law → coefficients → body forces and moments → gear contacts → integrate velocity, position, angular rate (Euler's equations) and the orientation quaternion.

## Where data lives

- Settings and passed lessons: `UserDefaults` (domain `com.amalmehta.topgunsimulator`).
- Feedback: `~/Library/Application Support/Top Gun Simulator/feedback.jsonl`.
- No network access, no accounts, and no files are read from the user.

## Key decisions and trade-offs

- **Stability-derivative model, not blade-element:** mid-fidelity is enough to teach real stick-and-rudder behaviour (stalls, trim, adverse yaw, P-factor, ground effect) while staying small and deterministic. Mach effects, engine systems and weight and balance are left out.
- **Body axes match SceneKit** (−Z forward, +Y up), so the physics quaternion drives nodes directly. Aero quantities are converted to conventional p/q/r and α/β for the maths and the instruments.
- **Fixed 240 Hz substeps** with semi-implicit Euler keep the stiff gear springs stable and make tests deterministic.
- **Pure `FlightCore`** lets tests fly whole lessons with a scripted pilot without any UI.
- **Analytic terrain** is shared by physics, rendering and both 2D views, so they always agree. The cost is that it isn't real-world scenery.
- **SceneKit primitives** instead of imported 3D assets: no asset pipeline and animated control surfaces for free, but simpler-looking aircraft.
- **Main-thread loop** (Timer) instead of the SceneKit render thread: simpler under Swift concurrency, and physics costs well under 1 ms per frame.
- **Auto-rudder on by default** for learners, including a heading-hold on the takeoff roll. It can be turned off in Settings to feel adverse yaw and P-factor.

## Testing

`swift test` runs 26 XCTest cases in `Tests/FlightCoreTests`: ISA values, terrain shape, Euler round-trip, hands-off trim stability (both aircraft), control response directions, the lift curve and stall, stall and recovery, takeoff distance and tracking, sitting still on the runway, fighter takeoff and gear, the g-limiter, gentle vs. hard landings, gate crossing, gun cone, bandit merge, instructor priorities, every lesson starting cleanly, steps not advancing early, the flat approach corridor, and scripted pilots passing the Controls and Takeoff lessons. The app was checked by launching it with `--start` flags and capturing window screenshots (`scripts/screenshot.sh`).

## Known limits

- The keyboard is a coarse stick, so a game controller flies much better. There is no mouse-yoke mode.
- No sound, weather visuals, night or multiplayer.
- The bandit is a single pursuit AI. It doesn't do energy tactics or defensive breaks.
- The landing lesson is graded on touchdown sink rate and runway position, not on a full approach-stability score.
- Startup takes a few seconds while the terrain mesh and map image are generated.
- Mac only for now. A website version is a planned later step.
