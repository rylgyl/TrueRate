# TrueRate

A macOS menu bar app that automatically matches your DAC's sample rate to the
track Apple Music is playing — a from-scratch, more reliable take on
LosslessSwitcher.

## How it works

- Runs a **live filtered stream** of Apple Music's unified log
  (`/usr/bin/log stream --predicate ...`) and parses the
  `Creating AudioQueue with format: ... sampleRate:NNN` and
  `ACAppleLosslessDecoder ... from N-bit source` lines that fire the moment a
  track's audio pipeline is built. Streaming (vs. polling the log store on a
  timer) means detections arrive within milliseconds and none are missed.
- On startup it also scans the last 5 minutes of logs so the currently playing
  track is picked up immediately.
- Sets the output device's nominal sample rate via CoreAudio
  (`kAudioDevicePropertyNominalSampleRate`). If the exact rate isn't supported,
  it picks the best rate in the same family (e.g. 88.2 for a 176.4 track on a
  96k-max DAC).
- Follows the system default output device (reacts to device changes), or you
  can pin a specific device in the panel.
- If the log stream dies (e.g. logd restarts), it relaunches itself after 3s.

## UI

Menu bar shows a waveform icon + the device's current rate. The dropdown panel
shows: detected track rate/bit depth vs device rate with a match indicator,
current track name, output device picker, auto-switch toggle, recent switch
history, and launch-at-login.

## Requirements / notes

- Your user must be an **admin** (reading other processes' logs requires it).
- For rates above 48 kHz you must set Music ▸ Settings ▸ Playback ▸
  Audio Quality ▸ Streaming to **Hi-Res Lossless** — otherwise Music itself
  caps playback at 48 kHz and that's what gets detected.
- Don't run LosslessSwitcher at the same time; they'd fight over the device.

## Build

```sh
./build_app.sh          # builds and ad-hoc signs dist/TrueRate.app
ditto dist/TrueRate.app /Applications/TrueRate.app
open /Applications/TrueRate.app
```
