# 🎮 Gyro Engine

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Godot](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godot-engine&logoColor=white)](https://godotengine.org)
[![Platform](https://img.shields.io/badge/Platform-Android-brightgreen)](https://www.android.com)

Gyro Engine is a visual game engine built on top of [Godot 4.7](https://godotengine.org) that lets you create 2D games without writing code. Assemble game logic from colorful blocks, like a constructor, and build APKs directly on your phone.

<p align="center">
  <img src="docs/images/screenshot.png" alt="Gyro Engine" width="300">
</p>

## Features

### Visual Programming
- Assemble logic from blocks: Events → Conditions → Actions
- Drag & drop block editor
- Undo / Redo support
- Collapsible blocks for clean organization

### Gameplay
- Physics: gravity, collisions, rigid bodies, sensors, drag & drop
- Camera: follow objects, parallax backgrounds, smooth tracking
- Particles: snow, rain, fire, sparks, confetti presets
- Sound: play sounds and music (MP3, OGG, WAV), looping support
- Animations: spritesheet animations, tweens (smooth animations)
- Timers: one-shot and repeating timers

### Objects & Graphics
- Create objects: rectangles, text, sprites, circles, lines, spritesheet animations
- Gradients, borders, corner radius
- Layers (z-index)
- Tags and groups for mass operations
- Anchors for adaptive positioning on different screen sizes

### Logic & Data
- Variables: number, text, bool, table (dictionary/array)
- Conditions: always, variable equals/greater, payload equals/greater
- Loops: repeat N times, loop from-to, for each in table
- Expressions: math, comparison, logic operators, built-in functions

### UI Widgets
- Text input fields
- Sliders
- Toggles (checkboxes)

### Mobile Features
- Build APK directly on your phone
- Build with keystore signing
- Screen orientation (portrait / landscape / auto)
- Partial multitouch support
- Screen tap and touch events

### Data & Connectivity
- Save/load values
- Read/write files
- HTTP requests
- HTTP response events

### Project Management
- Import / export projects (.gyroproj)
- Auto-save with configurable interval
- Backup system (up to 3 backups)
- Built-in documentation

### Localization
- Russian and English languages
- Easy to add new languages

## Quick Start

### Running the Engine
1. Download [Godot Engine 4.7](https://godotengine.org/download)
2. Clone the repository:
   git clone https://github.com/YOUR_USERNAME/gyro-engine.git
3. Open the project folder in Godot Engine
4. Press F5 to run

### Building APK
1. Configure project settings (app name, package name, icon)
2. Create or import a keystore (.p12)
3. Tap "Build APK"
4. Choose save location

### Creating Your First Game
1. Tap + in Project Manager → enter name → Create
2. Open project hub → Structure → + → Script → name it "Main"
3. Open the script → + → Events → On start
4. Inside the event → + → Objects → Create object
5. Tap ▶ to play!

## Documentation

The engine includes comprehensive built-in documentation covering:
- Introduction and quick start
- Events, conditions, actions
- Physics, camera, particles, sound
- Objects, widgets, variables
- APK building, file operations
- FAQ and debugging tips

Access it via the Documentation button on the home screen.

## Requirements

- Godot Engine 4.7+
- Android device (for APK building)

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### How to Contribute
1. Fork the repository
2. Create a feature branch (git checkout -b feature/my-feature)
3. Commit your changes (git commit -m 'Add amazing feature')
4. Push to the branch (git push origin feature/my-feature)
5. Open a Pull Request

## License
This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Godot Engine](https://godotengine.org) — the amazing open-source game engine
- [Godot File Picker](https://github.com/pattlebass/Godot-File-Picker) — file picker addon for Godot

## Community

- Telegram: [@GyroEngine](https://t.me/GyroEngine)

Made with ❤️ by [ffsonDev](https://github.com/ffsonDev)
