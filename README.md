# HeadPointer

Move your Mac's cursor with AirPods Pro: turn your head, or hold one earbud in your hand like a laser pointer. Press the stem to click.

A port of the Mac half of [WatchPointer](https://github.com/umarz317/WatchPointer) by Umar Afzal. The Apple Watch is replaced by the head tracking AirPods already send to the Mac, so there is no companion app and no custom Bluetooth protocol.

## Requirements

- Mac with macOS 14 or later
- AirPods with head tracking (AirPods Pro, AirPods Max, AirPods 3rd gen or later), connected to the Mac
- Xcode command line tools (`swift`)

## Run it

```bash
./run.sh
```

`run.sh` builds a small `HeadPointer.app` in `.build/` and launches it, with logs in your terminal. Ctrl-C stops it.

The first time, macOS asks for **Motion & Fitness** and **Accessibility** access for HeadPointer. Allow both, then run it again. Accessibility is what lets it move the cursor.

It runs as its own app rather than through `swift run` because macOS asks the launching app (your terminal) for Motion access otherwise, and kills the process since terminals have no motion usage description.

## Controls

| Stem press | Action |
|---|---|
| 1× | Click |
| 2× | Re-center (aim at the middle of the screen first) |
| 3× | Pause / resume |

Stem presses arrive as media commands, so they only reach HeadPointer while it is the "now playing" app. If Music or Spotify is playing, that app gets them.

## Using an earbud as a pointer

In System Settings › Bluetooth › your AirPods › ⓘ, turn off **Automatic Ear Detection**, or the bud stops sending motion when it leaves your ear. Pinch one bud by its stem, point at the middle of the screen and press twice to re-center.

## Settings

```bash
./run.sh 1.2          # speed: higher = less turn to reach the edges
./run.sh steady=0.6   # steadier when holding still (default 0.8)
./run.sh quick=0.02   # less lag on fast moves (default 0.01)
```

## How it works

- Up/down comes from the earbud's pitch relative to where you re-centered.
- Left/right adds up turns around the real vertical (the gyroscope projected onto gravity), so it works however the bud is held. It drifts slowly; re-center to fix it.
- The aim is projected onto the screen like a laser hitting a wall, smoothed with a [1€ filter](https://gery.casiez.net/1euro/), and the cursor glides toward it 240 times a second to hide the ~25 Hz sample rate.

## Limits

- Main display only.
- No right-click, drag or scroll: AirPods have no buttons for them.
