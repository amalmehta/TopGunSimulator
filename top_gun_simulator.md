PROJECT NAME: top_gun_simulator

META-INSTRUCTIONS:

<Read it all before acting. Ask about anything unclear, contradictory or
 underspecified — before starting and mid-build. Ask in the question widget
 (AskUserQuestion): related questions batched, concrete options, your
 recommendation first. Plain text only if the widget isn't available.>

<Don't expand scope. Anything not listed here is a proposal, including changes
 to this file — propose it, don't do it.>

<Prefer doing over describing: run the code, write the files, test it.>

<Always in scope, no proposal needed: when it goes on GitHub, a README that is
 easy to read at a glance — a line on what it is, then clear visuals
 (screenshots, a diagram or a chart), then links. Everything else goes in
 linked files: docs/INSTRUCTIONS.md (setup, run, use),
 docs/SYSTEM-DESIGN.md (see below) and docs/FILE-STRUCTURE.md (what's where). If what you're
 building is an application rather than a script, also a small unobtrusive feedback tab, and a settings
 button or tab (⌘, on the Mac) that gathers its preferences in one place.>

<If what you're building is an application, build it as a Mac app first; the
 website comes after, as its own step.>

<When an application takes files as input, offer a visible Upload button that
 opens the file picker, accept files dragged anywhere onto the window (not
 only onto a small drop zone), and accept pasting them with ⌘V.>

<Color-code tags, categories and types by similarity: related ones share a
 hue family, with shades far enough apart to tell them apart at a glance, in
 both light and dark mode.>

<Name things the way a person would say them — "Goal Tracker", not
 goal_tracker — for the app, its windows, titles, files people open, repo
 descriptions and README headings. When you create the GitHub repo, name it
 with no "_" or "-": one word or joined words, e.g. GoalTracker.>

<Always in scope: a system design doc in the codebase, docs/SYSTEM-DESIGN.md,
 kept current as the build changes. Cover the architecture (with a Mermaid
 diagram), each component's job, the main flows, where data lives, the key
 design decisions and their trade-offs, how it's tested, and known limits.>

<Finish by listing every deliverable: path, what it is, how to check it works.>

<Git rules (no Claude attribution, never commit .claude/) are in
 ~/.claude/CLAUDE.md and apply on their own — nothing to repeat here.>

<Keep the changelog at the bottom current.>

CONTEXT:

you know what it is my g

DELIVERABLES:

full airplane simulator + 2d / 3d external viz. help me learn to fly

OPEN QUESTIONS / ASSUMPTIONS:

<Agent fills in: what it guessed, what it decided without asking.>

Asked and answered (2026-10-11):
- Flight model: mid-fidelity 6-DOF (stability derivatives, stalls, ground effect, gear physics).
- Aircraft: a Cessna-172-like trainer for the lessons plus an F/A-18-like fighter.
- "Help me learn to fly" = guided lessons + live instructor HUD + free flight + Top Gun missions (canyon run, dogfight).
- Stack: native SwiftUI + SceneKit Mac app.

Decided without asking:
- "2D / 3D external viz" = 3D world (chase, cockpit, orbit and tower cameras) plus 2D moving map, side profile with 3° glidepath, and six-pack instruments.
- 11 lessons; pass/fail checks hold for N seconds; progress is saved locally.
- Keyboard + game controller input; no mouse yoke.
- Auto-rudder on by default for learners (switchable).
- No file input, so no Upload button, drag-and-drop or ⌘V paste.
- Feedback is saved locally (feedback.jsonl); there is no server to send it to.
- Built with SwiftPM + a bundling script rather than an Xcode project.
- Fictional world: one airport, hills, a mountain range with a canyon. No real-world scenery.
- Added `--start` / `--camera` launch flags for demos and screenshots.
- Not on GitHub yet: the folder isn't a git repo. Creating the repo (suggested name TopGunSimulator) waits for approval.
- The website version is a later, separate step (not started).

Website (2026-10-11), asked and answered: TypeScript + Three.js port; full parity with the Mac app; GitHub Pages from the same repo (web/ folder); feedback opens a pre-filled GitHub issue.
Website, decided without asking:
- Vite + plain DOM (no UI framework); Vitest for tests.
- The physics port is verified against golden trajectories exported from the Swift model.
- Touch controls (added 2026-10-11, user chose on-screen stick + throttle): virtual stick, rudder, throttle and buttons, auto-on for touch screens with a Settings override; compact phone layout with a lesson strip; key hints reworded for touch.
- Tilt-to-fly (added 2026-10-11, requested as a Settings option): off by default; gravity-vector based; neutral captured at flight start or with a Level button; on-screen stick overrides; iOS permission asked from the toggle or an in-flight Enable tilt button.
- `?start=` / `?camera=` URL parameters mirror the Mac launch flags.
- Settings shortcut ⌘, (Ctrl+, elsewhere) plus a gear button.

CHANGELOG:

- 2026-10-11 — created
- 2026-10-11 — added tilt-to-fly as a Settings option (web)
- 2026-10-11 — added touch controls for phones and tablets (web)
- 2026-10-11 — built the website version (web/, Three.js port, golden-trajectory parity tests, GitHub Pages deploy)
- 2026-10-11 — built v1: Mac app (FlightCore + SwiftUI/SceneKit), 11 lessons, instructor, 3D/2D views, settings, feedback, docs, 26 tests
- 2026-09-15 — added meta-instruction: built-out applications include a small feedback tab
- 2026-09-15 — added meta-instruction: no "Claude" attribution in commits, PRs, or branches
- 2026-09-16 — added meta-instruction: always include a README when adding to GitHub
- 2026-09-16 — changed meta-instruction: ask clarifying questions in the question widget
- 2026-09-17 — added meta-instructions: Claude never a contributor; never commit .claude/
- 2026-09-26 — compressed the meta-instructions and every field prompt; git rules moved to the global instruction file
- 2026-09-27 — added meta-instruction: applications are built as a Mac app first, then a website
- 2026-09-28 — folded inputs, instructions, constraints, deliverables and done criteria into one free-form CONTEXT
- 2026-09-28 — changed meta-instruction: a README on GitHub always includes a visual
- 2026-09-28 — added meta-instruction: name things like a person would, never snake_case
- 2026-09-28 — changed meta-instruction: README leads with visuals; instructions live in a linked guide
- 2026-09-28 — changed meta-instruction: README is visuals and links; details in docs/INSTRUCTIONS.md and docs/FILE-STRUCTURE.md
- 2026-09-29 — changed meta-instruction: GitHub repo names have no "_" or "-"
- 2026-10-02 — added a DELIVERABLES field after CONTEXT
- 2026-10-02 — added meta-instruction: every project has a system design doc at docs/SYSTEM-DESIGN.md
- 2026-10-05 — added meta-instruction: applications include a settings button or tab
- 2026-10-08 — added meta-instruction: color-code tags by similarity (related share a hue family, each distinct)
- 2026-10-09 — added meta-instruction: apps that take files have an Upload button, drop anywhere, and paste
