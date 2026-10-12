# Top Gun Simulator: Instructions

There are two versions with the same physics, lessons and controls:

- **Mac app:** native SwiftUI + SceneKit (below).
- **Website:** TypeScript + Three.js in `web/`, live at https://amalmehta.github.io/TopGunSimulator/ (see [Web version](#web-version)).

## Requirements

- macOS 14 or later
- Xcode 15+ (or its command-line tools with Swift 5.10+)

## Build and run

```bash
scripts/build-app.sh
```

This builds a release binary and wraps it as `build/Top Gun Simulator.app` (with its icon). Open it from Finder, or:

```bash
open "build/Top Gun Simulator.app"
```

During development you can also run `swift run TopGunSimulator`.

Start straight into a flight (useful for demos):

```bash
"build/Top Gun Simulator.app/Contents/MacOS/Top Gun Simulator" --start landing --camera Chase
```

`--start` takes a lesson id (`controls`, `straight-level`, `power-pitch`, `turns`, `climbs-descents`, `stalls`, `takeoff`, `landing`, `jet-fam`, `canyon-run`, `dogfight`) or `free-trainer`, `free-fighter`, `air-trainer`, `air-fighter`. `--camera` takes `Chase`, `Cockpit`, `Orbit` or `Tower`.

## Test

```bash
swift test
```

26 tests cover the atmosphere, terrain, trim and stability, stalls, takeoff, landing and crash detection, the fighter's g-limiter, gates, guns, the bandit AI and lesson flow. Two of them have a scripted pilot fly whole lessons to a pass.

## Web version

Requires Node 20.19+ (22+ recommended).

```bash
cd web && npm install
```

```bash
npm --prefix web run dev
```

That serves http://localhost:5173. Open a flight directly with `?start=<lesson id or free-trainer|free-fighter|air-trainer|air-fighter>&camera=<Chase|Cockpit|Orbit|Tower>`.

```bash
npm --prefix web test
```

That runs 36 tests, including replays of reference trajectories exported from the Swift flight model, to prove both versions fly identically. To regenerate the references after changing the Swift physics:

```bash
GOLDEN_OUT="$PWD/web/tests/fixtures/golden.json" swift test --filter GoldenExport
```

Production build: `npm --prefix web run build` writes `web/dist/`. Every push to `main` that touches `web/` runs the tests, builds and deploys to GitHub Pages (`.github/workflows/pages.yml`).

Web differences: settings and lesson progress live in the browser's localStorage; the Feedback button opens a pre-filled GitHub issue; ⌘, (Ctrl+, on Windows/Linux) or the gear button opens Settings; on phones and tablets, on-screen touch controls appear automatically (see below).

### Touch controls (phones and tablets)

- **Stick** (bottom-left): drag down to pull back (nose up), up to push forward, sideways to roll. It springs back to centre when you let go.
- **Rudder** (above the stick): hold ◀ or ▶.
- **Throttle** (bottom-right): slide up for power. It stays where you leave it.
- **Buttons:** Flaps ▲/▼, Trim ▲/▼, Gear (fighter), Cam, Brake (hold), Guns (fighter, hold).
- On phones the instrument panel starts hidden so the 3D view has room. In landscape the sidebar is hidden too, and a lesson strip shows the current step; the toolbar buttons bring the panels back. Lesson and instructor text say "drag the stick down" instead of "S / ↓".
- Settings → Flying → Touch controls: Automatic (touch screens), Always on, or Off. You can fly with the stick and change the throttle at the same time (multi-touch).

### Tilt to fly (optional)

Settings → Flying → **Tilt to fly**. Tilt the top of the device toward you to pull up, away to push down, and tip it left or right to roll. About 30° from your neutral hold gives full stick.

- Your neutral hold is captured when the flight starts. Tap **Level** (next to the rudder buttons) any time to make the current hold straight and level.
- iPhone and iPad ask for motion access when you switch it on. After a page reload, iOS needs one tap on **Enable tilt** to allow it again.
- Touching the on-screen stick overrides tilt while your finger is on it. Throttle, rudder and the buttons work as usual.
- It works in portrait and landscape. Stick sensitivity and Invert pitch apply to tilt too. Lesson text says "tilt the top toward you" instead of "drag the stick down".

## How to learn to fly with it

1. **Lessons 1–3 (Basics, trainer):** the controls, straight and level with trim, and how power and pitch work together.
2. **Lessons 4–6 (Maneuvers):** turns, climbs and descents, slow flight and stalls.
3. **Lessons 7–8:** takeoff and landing. On the approach, keep two white and two red PAPI lights (left of the runway); the side profile shows the 3° glidepath.
4. **Lessons 9–11 (Top Gun, fighter):** jet familiarisation, the canyon run and the dogfight.

The **Instructor** panel explains what the aircraft is doing as you fly ("slipping: step on the right rudder", "stall: push forward") and, with *Hints + why*, the aerodynamics behind each tip. The **Controls** box in the instrument panel shows your stick next to what the control surfaces are actually doing.

Passed lessons get a check mark on the home screen. Settings → Instructor resets them.

## Controls

| Key | Action |
|---|---|
| S / ↓ | Stick back: nose up |
| W / ↑ | Stick forward: nose down |
| A D / ← → | Roll |
| Q / E | Rudder |
| R / F | Throttle up / down (hold) |
| [ / ] | Flaps up / down |
| , / . | Trim nose down / up |
| G | Gear (fighter) |
| B | Brakes (hold) |
| Space | Guns (fighter) |
| C | Next camera. Drag the 3D view to orbit; scroll to zoom. |
| P | Pause |
| I / M | Toggle the instrument panel / sidebar |
| \\ | Restart |
| Esc | End flight |
| H | Controls help |
| ⌘, | Settings |

Game controller: left stick flies, right stick is rudder, triggers set the throttle, A fires, B brakes.

## Settings (⌘, or the gear button)

- **Flying:** auto-rudder, invert pitch, stick sensitivity, keyboard re-centering speed
- **Instructor:** off / hints / hints + why; reset lesson progress
- **Display:** HUD, instrument panel, sidebar, aviation or metric units, field of view
- **World:** wind speed and direction, turbulence, bandit skill

## Feedback

The small **Feedback** button saves notes locally to `~/Library/Application Support/Top Gun Simulator/feedback.jsonl`. *Show file* reveals it in Finder.
