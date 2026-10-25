# flxrecord

Frame-accurate recorder and instant-replay buffer for HaxeFlixel, with a PNG-sequence sink
and an ffmpeg mux helper.

## Why

`FlxG.signals.postDraw` already hands you the finished frame — HUD, shaders, camera fades
and all. Recording from there means the capture matches what the player saw, without
replaying the scene into a second camera.

The output rate is independent of the game's framerate: a 240 fps game records at 30 fps
without skipping logic, and a 30 fps game records at 60 fps by duplicating frames.

## What is in here

| File | Role |
| --- | --- |
| `FlxRecorder` | Drives capture from `postDraw`, paces output to `fps` |
| `FlxReplay` | Ring buffer of the last N seconds, dumped on demand |
| `FrameSink` | Where frames go |
| `sinks/SequenceSink` | PNG sequence on disk |
| `VideoExport` | Muxes a sequence into mp4 through ffmpeg |

A sink is called on the main thread with a `BitmapData` that is already a private copy, so
it may keep the reference and encode off-thread.

## Requirements

Haxe 4.3, `flixel` 6.2.0, `openfl` 9.5.2, `lime` 8.3.2. `VideoExport` needs an `ffmpeg`
binary on `PATH` (or an explicit path).

## Install

```bash
haxelib dev flxrecord /path/to/flxrecord
```

Then `<haxelib name="flxrecord"/>` in `Project.xml`. Only include it where a state actually
records — the recorder itself is cheap when idle, but the sink is not.

## Licence

MIT. See `LICENSE.md`.
