# Top Gun Simulator

A Mac flight simulator that teaches you to fly: real aerodynamics, a live instructor, 11 guided lessons from "what does the stick do" to landing, then a fighter jet for a canyon run and a guns-only dogfight.

![Lesson 1 in the trainer: 3D chase view, HUD, lesson panel, map, side profile and instrument panel](docs/screenshots/lesson-chase.png)

| Flight school | Canyon run | Dogfight (cockpit) |
|---|---|---|
| ![Home screen with colour-coded lessons](docs/screenshots/home.png) | ![Fighter threading the canyon gates](docs/screenshots/canyon-run.png) | ![Fighter HUD with the bandit boxed](docs/screenshots/dogfight-cockpit.png) |

```mermaid
flowchart LR
    Keys[Keyboard / gamepad] --> Input[Input manager]
    Input --> Session[Flight session<br/>240 Hz physics]
    Session --> Lessons[Lessons + instructor]
    Session --> Scene[3D world<br/>SceneKit]
    Session --> Panels[HUD · instruments · 2D map · profile]
```

- **[How to build, run and fly](docs/INSTRUCTIONS.md)**
- **[System design](docs/SYSTEM-DESIGN.md)**
- **[What's where](docs/FILE-STRUCTURE.md)**
