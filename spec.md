# Puzzle Graph — Product & Technical Specification

**Platform:** Android
**Version:** 1.0 (draft)
**Date:** 2026-10-22

---

## 1. Overview

Puzzle Graph is an offline Android jigsaw puzzle game. The player picks one of 5 bundled images, a piece count, and a cut style. The app then generates a puzzle. The player drags pieces from a tray at the bottom of the screen onto a board at the top. The board can be zoomed and panned so the player can work on enlarged sections. The player can save progress, reset the puzzle, and ask for hints.

### 1.1 Goals
- Smooth play at every piece count up to ~1024 pieces on mid-range devices.
- Works in both portrait and landscape, with no loss of state on rotation.
- Ships as both 64-bit and 32-bit builds.

### 1.2 Non-Goals (v1)
- Importing images from the user's gallery or camera.
- Online features: multiplayer, leaderboards, cloud sync.
- Piece rotation (all pieces keep their correct orientation).
- In-app purchases or ads.

---

## 2. Core Flow

```
Launch → Home / Image Select → Puzzle Setup (pieces + style) → Play Screen
                ↑                                                  │
                └────────────── Android Back button ───────────────┤
                                                                   │
                                                     Completion Screen
```

1. **Home / Image Select:** a grid of the 5 bundled images. Images that have a saved game show a "Continue" badge.
2. **Puzzle Setup:** choose the piece count and cut style, then tap **Start**.
3. **Play Screen:** the board on top, the tray on the bottom, and the menu button in the top-right corner. The Android Back button auto-saves and returns to Home.
4. **Completion:** when the last piece is placed, play a celebration animation and show the elapsed time, the number of hints used, and the options **Play Again** and **Choose Another Image**.

---

## 3. Bundled Images

| ID | Asset | Notes |
|----|-------|-------|
| `img_01` | `puzzles/img_01.webp` | Placeholder; final art TBD |
| `img_02` | `puzzles/img_02.webp` | |
| `img_03` | `puzzles/img_03.webp` | |
| `img_04` | `puzzles/img_04.webp` | |
| `img_05` | `puzzles/img_05.webp` | |

**Requirements**
- Source resolution of at least **4096 × 3072** (4:3) so pieces stay sharp at ~1024 pieces and when zoomed in.
- WebP format, lossy quality of about 90, to keep the APK small.
- All 5 images use a 4:3 landscape aspect ratio so the grid math is consistent.
- Each image ships with a thumbnail (about 512 px) for the selection screen.
- At load time, the source is downsampled to fit the device's memory budget (see §9).

**Asset contract** (for whoever produces the final art):
- Put the files in `puzzles/` as `img_0N.webp` plus `img_0N_thumb.webp`. Replacing the placeholders with the same names needs no code change.
- Titles and paths live in `puzzles/catalog.json` (`id`, `title`, `image`, `thumb`). Change the titles there.
- After adding or replacing files, re-import once by opening the project in the Godot editor or running `godot --headless --import`. Textures import as lossy at 90% quality by default (`[importer_defaults]` in `project.godot`).

---

## 4. Piece Count

The player chooses from five sizes. Each size starts from a nominal target (64 to 1024) and is adjusted so the pieces come out close to square on a 4:3 image. The Setup screen labels each button with the **exact** piece count (63, 130, 252, 520, 1036) and shows the grid below the buttons.

| Option label | Grid (cols × rows) | Actual pieces | Piece aspect (w : h) |
|:------------:|:------------------:|--------------:|:--------------------:|
| 64           | 9 × 7              | 63            | 1.04 : 1 |
| 128          | 13 × 10            | 130           | 1.03 : 1 |
| 256          | 18 × 14            | 252           | 1.04 : 1 |
| 512          | 26 × 20            | 520           | 1.03 : 1 |
| 1024         | 37 × 28            | 1036          | 1.01 : 1 |

**Formula** (for any image aspect `A = width / height` and target `N`):
`rows = round(sqrt(N / A))`, `cols = round(N / rows)`.
This means the grid adapts automatically if an image with another aspect ratio is ever added.

---

## 5. Cut Styles

There are two cut styles in v1. Both are generated procedurally from a **seed**, so a saved puzzle can be rebuilt with identical shapes.

| Style | Description |
|-------|-------------|
| **Ribbon Cut** | A regular grid using the `cols × rows` layout from §4. Every interior edge gets a rounded knob (tab) on one side and a matching socket (blank) on the other. Pieces alternate in a checkerboard between two types: type A has tabs left and right and blanks top and bottom, and type B is the reverse. This gives the uniform ribbon look of commercial ribbon-cut puzzles. Knobs are Bézier curves with only small random changes in size and offset, so pieces look consistent but not identical. |
| **Random Cut** | Irregular pieces. Start from the `cols × rows` grid of §4 and move every interior grid corner by up to ±12% of a cell, so piece sizes and edge angles vary. Each interior edge gets a slight random bow, a knob with random direction, size (±15%) and position along the edge (±7%). Piece count is the same as Ribbon Cut. A repair pass re-cuts any piece whose knobs would collide, using smaller, centred knobs. |

**Generation requirements**
- Every interior edge is shared by exactly two pieces, and both pieces use the same curve with opposite orientation, so neighbors fit perfectly.
- Edge pieces always have a straight outer border.
- Generating ~1024 pieces must finish in **under 1.5 s** on the reference device (see §10), on a background thread, with a progress indicator.
- Each piece is stored as a polygon outline (the flattened curves), a bounding box, and its correct ("home") position.

---

## 6. Play Screen UI

### 6.1 Layout

**Portrait**
```
┌───────────────────────────┐
│ Puzzle Graph   ⏱ 03:12  ☰ │  ← top bar, menu in the top right
├───────────────────────────┤
│                     ┌───┐ │
│        PUZZLE BOARD │map│ │  ~65% of height
│   (zoomable / pannable)───┘│
│                           │
├───────── ═══ ─────────────┤  ← draggable divider
│ TRAY              214 left │
│ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ → │  ~35% of height, scrolls sideways
│ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ → │
└───────────────────────────┘
```

**Landscape**
The board still sits on top and the tray at the bottom. The tray shrinks to about 25% of the height, uses one or two rows, and scrolls sideways so the board keeps as much room as possible.

```
┌──────────────────────────────────────────────┐
│ Puzzle Graph                   ⏱ 03:12    ☰  │
├──────────────────────────────────────────────┤
│                 PUZZLE BOARD           [map] │  ~75%
├──────────────────────────────────────────────┤
│ TRAY ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ → │  ~25%
└──────────────────────────────────────────────┘
```

- The player can drag the divider between the board and the tray to resize them, between 15% and 50% tray height. The app remembers the chosen size separately for each orientation.
- Rotating the device keeps all state: board zoom and pan, piece positions, tray scroll, and the timer.

### 6.2 Puzzle Board
- Shows the target area as a faint outline of the finished puzzle.
- **Zoom:** pinch to zoom from 1× (whole puzzle fits) to **8×**. Double-tap toggles between 1× and 3×, centered on the tap point.
- **Pan:** two-finger drag at any zoom level. A one-finger drag on empty board space also pans.
- **Minimap:** when zoom is above 1.5×, a small overview appears in a corner. It shows the puzzle area, the pieces placed so far, and a rectangle for the current viewport. Tapping or dragging on the minimap moves the viewport there. The minimap hides itself at 1.5× zoom or below.
- Pieces can sit anywhere on the board, not just in their correct spot, so the player can stage pieces there.

### 6.3 Tray
- Holds every piece that hasn't been placed on the board yet. At the start, all pieces are in the tray in shuffled order.
- Pieces appear at a uniform thumbnail size in a grid that scrolls sideways. Only visible pieces are drawn.
- The tray's header bar shows a counter for how many pieces are left. Two buttons sit on its right:
  - **Sort Edges** moves edge pieces to the front of the tray in this order: the top row (left to right), the left column (top to bottom), the right column (top to bottom), then the bottom row (left to right). Interior pieces follow in their current order.
  - **Scramble** shuffles the tray into a new random order.

  Both scroll the tray back to the start and count as an unsaved change.
- Dragging a piece from the tray onto the board moves it there at the board's current zoom scale. Dragging a loose piece from the board back onto the tray returns it to the tray.

### 6.4 Piece Interaction
- **Pick up:** touch and drag. The piece lifts with a slight scale-up (1.05×) and a drop shadow, and comes to the front.
- **Snap:** when the player drops a piece within a **snap tolerance** of its correct position, it snaps into place. The tolerance is 25% of the piece's width, measured in board coordinates. A snap triggers a short haptic tick and a sound. Locked pieces can't be moved again.
- Only one piece can be dragged at a time.

### 6.5 Top Bar
- Title and image name (shortened if long).
- Timer. It pauses when the app goes to the background.
- **Menu button (☰) in the top-right corner.**

### 6.6 Look & Feel: Wooden Tabletop
The game is meant to feel like a puzzle laid out on a wooden table.
- **Table:** tiled oak planks behind every screen. On the Play screen the table is drawn in world space, so it pans and zooms with the pieces.
- **Puzzle mat:** green felt inside the puzzle frame, with a raised walnut rim and a soft shadow on the table.
- **Tray:** a darker walnut bed. Its grain scrolls with the pieces.
- **Chrome:** the top bar, tray divider, menu popup and dialogs use dark walnut planks with brass nails.
- **Buttons:**
  - normal buttons are oak with dark "burned" text;
  - selected or pressed buttons are honey wood with a brass rim;
  - primary actions (Start, Continue) are cherry.
- **Source art:** the textures were made in Pixelorama and are stored in `assets/ui/`, with editable `.pxo` sources in `assets/ui/src/`. The nine-patch textures are 96 px with 24 px borders and use lossless import. The tiling textures (table, tray, felt) are seamless and mipmapped.

---

## 7. Menu (Top Right)

| Item | Behavior |
|------|----------|
| **Hint** | Picks a random unplaced piece. That piece is **highlighted** with a pulsing glow outline: in the tray, the tray scrolls to it, and on the board, the view pans to it. At the same moment, its **target location on the board is highlighted** with a pulsing outline of the piece's shape. If the target is off-screen, the board pans and zooms to show it. The highlight lasts 4 seconds or until the player touches the piece. The hint count is shown on the completion screen. |
| **Save Puzzle** | Saves the current state right away (see §8) and confirms with a toast: "Puzzle saved". |
| **Exit to Main Menu** | Returns to the Home screen. If everything is saved, it leaves right away. If there are changes since the last save (manual or auto), a dialog asks: "Your latest progress isn't saved. Are you sure you want to leave?" with **Save & Leave**, **Leave** (discard changes since the last save) and **Cancel**. |
| **Reset Puzzle** | Shows a confirmation dialog: "Reset puzzle? All progress will be lost." On confirm, every piece goes back to the tray in a new shuffled order, the timer and hint count go back to zero, and the saved game is deleted. The cut seed stays the same, so the shapes don't change. |

---

## 8. Save System

### 8.1 What Is Saved
```json
{
  "schemaVersion": 1,
  "imageId": "img_03",
  "pieceTarget": 256,
  "cutStyle": "RIBBON",
  "seed": 8734120934,
  "elapsedMs": 192000,
  "hintsUsed": 2,
  "board": { "zoom": 2.4, "panX": 310.0, "panY": 128.5 },
  "pieces": [
    { "id": 0, "state": "LOCKED" },
    { "id": 1, "state": "BOARD", "x": 1022.4, "y": 87.1, "z": 0 },
    { "id": 2, "state": "TRAY",  "trayIndex": 17 }
  ],
  "placed": 121,
  "total": 252,
  "savedAt": "2026-10-22T14:03:00Z"
}
```
- `z` is the stacking order of loose board pieces. `placed` and `total` drive the "Continue · N%" badge. Positions are in board units: the puzzle is 3000 units tall regardless of texture resolution.
- Piece shapes are **not** stored. They are rebuilt from `imageId`, `pieceTarget`, `cutStyle`, and `seed`.
- Saves are JSON files in app-private storage. A ~1024-piece save is under 100 KB.

### 8.2 Save Behavior
- **Manual save** from the menu.
- **Auto-save:**
  - when the app goes to the background or is closed,
  - when the player leaves the Play Screen with the Back button,
  - every 60 seconds of active play,
  - right after each piece snaps into place, at most once every 5 seconds.

  Auto-save is silent. A small "saved" icon flashes briefly in the top bar.
- **One save slot per image.** Starting a new configuration of an image that already has a save asks the player: "Overwrite saved progress?"
- The home screen shows "Continue" with a progress percentage on any image that has a save.
- Saves are written atomically: write to a temp file, then rename, so a crash can't corrupt them.

---

## 9. Rendering & Performance

- **Piece rendering:** each piece is a pre-triangulated `ArrayMesh`, built once after generation and UV-mapped onto the single source texture, so no per-piece bitmaps are needed. The board, tray, minimap and drag layer all draw these meshes with `draw_mesh()` and a thin outline.
- **Redraw strategy:** the board's piece layer is redrawn only when a piece moves or locks. Panning and zooming only change the layer's transform. The piece being dragged is drawn on a separate full-screen overlay. The tray draws only its visible slots.
- **Threading:** cut generation and triangulation run on a worker `Thread`. Mesh creation runs on the main thread. Measured on desktop: 1036 Random Cut pieces in about 175 ms, and the whole 1036-piece puzzle ready in about 300 ms.
- **Memory budget:** the source image texture is capped by device RAM. It is 4096 px on the long edge on devices with 4 GB of RAM or more, and 2048 px on devices with less RAM or 32-bit devices.
- **Hit testing:** loose pieces are checked top-down with a bounding-box test, then an exact point-in-polygon test. If nothing hits exactly, the nearest piece centre within a finger-sized radius is picked. A spatial index is only worth adding if profiling shows a need.
- **Targets:** 60 fps while dragging and zooming with ~1024 pieces on the reference device. Cold start to Home screen in under 2 s.

---

## 10. Technical Requirements

| Item | Value |
|------|-------|
| Engine / language | **Godot 4.7, GDScript**, Compatibility renderer (OpenGL ES 3.0) |
| UI orientation | `sensor` (portrait and landscape). Stretch mode `canvas_items` / `expand`, base 720 × 1280 |
| Min Android version | 7.0 (API 24) |
| Target SDK | Latest stable that Google Play requires at release |
| Reference device | A mid-range device with 4 GB of RAM (e.g., Pixel 6a-class) for performance targets; a low-end 2 GB 32-bit device for minimum spec |

### 10.1 64-bit and 32-bit Builds

| ABI | Bitness | Required |
|-----|---------|----------|
| `arm64-v8a` | 64-bit | ✅ |
| `armeabi-v7a` | 32-bit | ✅ |
| `x86_64` | 64-bit | ✅ (emulators / Chromebooks) |

- **Google Play distribution:** upload one Android App Bundle (AAB) containing all ABIs. Play delivers the right one to each device.
- **Sideload distribution:** build separate APKs for each ABI (`puzzlegraph-arm64-v8a.apk`, `puzzlegraph-armeabi-v7a.apk`), plus one universal APK.
- 64-bit native libraries must be aligned to a **16 KB page size** to meet current Play requirements.
- Both builds must be tested to completion on a 64-bit and a 32-bit device or emulator.

**Export presets** (`export_presets.cfg`, all output to `build/android/`):

| Preset | ABIs | Output |
|--------|------|--------|
| Android 64-bit (arm64-v8a) | arm64-v8a | `puzzlegraph-arm64-v8a.apk` |
| Android 32-bit (armeabi-v7a) | armeabi-v7a | `puzzlegraph-armeabi-v7a.apk` |
| Android x86_64 (emulator) | x86_64 | `puzzlegraph-x86_64.apk` |
| Android Universal | all three | `puzzlegraph-universal.apk` |

Build with `godot --headless --export-debug "<preset name>"`, or `--export-release` once a release keystore is configured. The Play Store AAB needs a Gradle build: install the Android build template, then set `gradle_build/use_gradle_build=true` and `export_format=1`.

---

## 11. Future Considerations (Post-v1)
- More cut styles: classic jigsaw, square (no knobs), whimsy pieces.
- Piece rotation mode (90° steps) as a difficulty option.
- Neighbor joining: pieces that fit together off-target move as a group.
- Tray filters: edge pieces only, sort by color.
- Settings screen: ghost image, timer visibility, sound, haptics.
- User-supplied images from the gallery or camera.

---

## 12. Acceptance Criteria

1. All 5 bundled images can be started with every piece-count option and both cut styles.
2. Neighboring pieces fit together exactly, with no gaps or overlaps, in both styles.
3. The board is on top and the tray is at the bottom in both portrait and landscape. Rotating the device mid-game loses no state.
4. Pinch zoom (1×–8×), pan, and double-tap zoom work, and pieces can be dragged and snapped while zoomed in. The minimap appears above 1.5× zoom and moves the viewport when tapped.
5. The menu button sits in the top-right corner and offers **Hint**, **Save**, and **Reset**, all working as described in §7.
6. Hint highlights both a random unplaced piece and its correct board location, and brings both into view.
7. Auto-saved progress, after the app is force-closed, comes back with identical piece shapes and positions. At most 60 seconds of progress is lost.
8. The app installs and plays through completion on both a 64-bit (`arm64-v8a`) and a 32-bit (`armeabi-v7a`) device or emulator.
9. A ~1024-piece puzzle holds at least 55 fps while dragging on the reference device and doesn't crash with out-of-memory on the 2 GB minimum-spec device.
