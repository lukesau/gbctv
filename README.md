# ![banner](./banner.png)

## Learned-code mode

This branch turns GBCTV into an IR measurement instrument plus a practical
learning remote, by grafting in the pulse-width engine reverse engineered from
`gbc-remote.gbc`. Builds with RGBDS 1.0.

| Button | Mode | What it does |
|---|---|---|
| A | Raw Capture | Original max-rate sampler: dumps `RP` every ~4.3&micro;s (double-speed) into the profile's SRAM bank (~33ms window), then **auto-derives a learned code from the same capture** (`IRConvertRaw`). The "logic analyzer" mode. |
| B | Raw Replay | Streams a raw capture back out of the LED at the same rate. |
| Start | Learn Code | Ported gbc-remote recorder: OR-filtered envelope detection, pulse widths stored as ~100&micro;s run-length counts, two frames (code + repeat). |
| Select | Send Code | Ported gbc-remote transmitter. Hold to repeat (uses frame 2 if one was recorded). |
| ←/→ | Profile | Selects the SRAM bank (16 &times; 8KB). |

Raw and learned data coexist in each bank, and the header's flag byte
tracks provenance: `raw+rle` means the learned widths were derived from
that exact raw capture (one button press, two representations — the raw
buffer is a strict superset of what the learner extracts, so conversion
runs offline after capture; truly simultaneous capture is impossible
since both are saturated cycle-counted CPU loops). A live Start-button
learn clears the raw flag, since the bank's raw bytes would then be from
a different press. Derived codes have an empty repeat frame (the ~33ms
raw window ends long before any protocol's ~100ms repeat), so held-send
falls back to re-sending frame 1. `parse_sav.py --check` re-derives the
widths from the raw samples on the PC and diffs them against what the
GBC stored.

### Getting data off the cart

Each profile bank starts with a 16-byte self-describing header (`"IR"` magic,
type, timing metadata — see `src/ram.asm`), so a save dumped by any means is
self-describing. On an EZ-Flash Jr, for example: launch the ROM, capture, then
reboot, and the kernel's BACKUPSAVE prompt writes the whole SRAM to
`SAVER/GBCTV.SAV` on the SD card. Parse the dump with:

```
python3 tools/parse_sav.py GBCTV.SAV            # pulse listing
python3 tools/parse_sav.py GBCTV.SAV --csv out.csv
```

All ported routines run at normal CPU speed and are instruction-identical to
the original ROM in every cycle-counted path; raw capture still uses
double-speed. One learned-width unit ≈ 105 M-cycles ≈ 100&micro;s; one raw
sample ≈ 9 double-speed M-cycles ≈ 4.3&micro;s.

---

Original README below.

![GitHub](https://img.shields.io/github/license/Hacktix/gbctv?style=for-the-badge)
![GitHub Release Date](https://img.shields.io/github/release-date/Hacktix/gbctv?label=Latest%20Release&style=for-the-badge)
![GitHub last commit](https://img.shields.io/github/last-commit/Hacktix/gbctv?style=for-the-badge)
![GitHub repo size](https://img.shields.io/github/repo-size/Hacktix/gbctv?style=for-the-badge)

## What's that?
GBCTV is a program which uses the Gameboy Colors infrared interface in order to record and play back IR signals. In essence - this program turns your Gameboy Color into a crappy TV remote!

## How do I use it?
You'll need to use a flashcart in order to get the ROM loaded on your actual device, as running it on an emulator probably wouldn't be very useful. You can grab the newest release [here](https://github.com/Hacktix/gbctv/releases) and simply just start it up.

### Recording Profiles
GBCTV offers a system of "recording profiles". These profiles work as sort of "slots" into which signals can be recorded. When no recording is in progress, the profile number can be switched by pressing left and right on the D-Pad.

### Recording Signals
Press the A button once prompted to start an IR recording. The program waits for an incoming IR signal before starting the recording. If the small recording-dot icon disappears before any signal was provided there was most likely some sort of interference. In this case, just hit A again until it records the signal properly. The recording overwrites anything else stored in the currently selected profile.

### Playing Back Signals
Pressing the B button (while no recording is in progress) starts playback of the signal stored in the currently selected Recording Profile. Holding down the B button loops this signal over and over.

**Note:** Pressing B before recording any signals will end up sending random signals and may cause unintended side effects. I would recommend against doing this.

## How does it work?
As soon as the A button is pressed, the program waits for an IR signal. Once it receives one it starts dumping the value of the IR register into SRAM (bank number dependant on the selected profile number) every few microseconds. The recording initiation mechanism of waiting for a "high" signal isn't an optimal solution as it's triggered by interference as well, but it works fine most of the time and eliminates the need for the user to synchronize button presses down to an accuracy of around 2 milliseconds.

Due to the high sample rate required to record IR pulses that only last up to 10 microseconds, RAM is the limiting factor here. The 8KB of SRAM banks is enough to record the aforementioned 2 milliseconds of signals, which should be good enough for most remotes, but may not suffice for every purpose imaginable.

## Plans for the future?
A feature which allows recording longer signals (~5ms instead of ~2ms) is in consideration, but not decided on yet. Of course, bugfixes and small QoL updates may be pushed at any time.
