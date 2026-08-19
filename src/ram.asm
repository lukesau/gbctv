SECTION "SRAM", SRAM[$A000]
;------------------------------------------------------------------------
; Per-bank layout (one profile = one 8KB bank, dumped by the EZ-Flash Jr
; kernel to SAVER/*.SAV). 16-byte self-describing header, then the
; learned-code arrays, then the raw sample buffer. Raw and learned data
; coexist so a raw capture can be converted in place into a sendable
; code from the exact same button press.
;
; sHdrType is a flag byte: SAVF_RAW / SAVF_RLE, set together ($03) only
; when the learned arrays were derived from the raw buffer in this bank.
; A live Start-button learn clears SAVF_RAW: the raw bytes would be from
; a different press, and the flags guarantee shared provenance.
;------------------------------------------------------------------------
sHdrMagic: ds 2             ; "IR" ($49 $52)
sHdrType: ds 1              ; SAVF_* flags
sHdrVersion: ds 1           ; SAV_VERSION
sHdrRawPeriod: ds 1         ; raw sample period, double-speed M-cycles
sHdrRawSpeed: ds 1          ; CPU speed during raw capture (2 = double)
sHdrRleUnit: ds 1           ; learned width unit, M-cycles
sHdrRleSpeed: ds 1          ; CPU speed for learned unit (1 = normal)
sHdrRleSource: ds 1         ; RLESRC_LIVE / RLESRC_DERIVED
sHdrPad: ds 7
sMarks1: ds $7f             ; frame 1 mark widths, 0-terminated
sSpaces1: ds $7f            ; frame 1 space widths (parallel array)
sMarks2: ds $7f             ; frame 2 (repeat frame) marks, 0-terminated
sSpaces2: ds $7f            ; frame 2 spaces
sArrayPad: ds 4             ; rounds the four $7f arrays up to $200, so the raw
                            ; buffer starts at a round $210 into the bank. The
                            ; arrays must stay $7f apart -- IRSend hardcodes
                            ; that stride to reach the spaces array.
sRawSamples: ds $1df0       ; raw mode: 1 byte per ~4.3us, bit 0 = light
ASSERT @ == $C000, "raw buffer must end at $C000, the capture loop bound"

SECTION "IR Work", WRAM0
wConvDark: ds 1             ; converter: current dark-run length, samples
wConvEntries: ds 1          ; converter: output slots remaining

SECTION "HRAM", HRAM
hInitialRegA: db            ; Initial value of the A register on bootup
hSelectedProfile: db        ; Selected profile number (= SRAM bank number)
hProfileCooldown: db        ; Amount of frames left during which the profile selection cannot be changed
