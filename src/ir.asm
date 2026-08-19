SECTION "IR Engine", ROM0

;------------------------------------------------------------------------
; Pulse-width IR engine, ported from gbc-remote.gbc (bank 0, $1AF6-$1C2A).
; Instruction sequences are kept byte-faithful wherever they are part of
; a cycle-counted timing path (including the nops). All routines run at
; NORMAL speed (1.05MHz M-clock); one record/replay unit is ~100us.
;
; Record buffers live directly in the current SRAM bank (sMarks1 etc.) --
; cart RAM has the same bus timing as the WRAM the original used, so the
; loop timing is unchanged and no copy step is needed before the EZ-Flash
; kernel dumps the bank to SAVER/*.SAV.
;------------------------------------------------------------------------

;------------------------------------------------------------------------
; IRSample - envelope sampler ("demodulator").
; ORs together 3 effective reads of the RP input bit spread over a ~25us
; window (about one 38kHz carrier period), so a point sample landing in
; a carrier gap mid-mark still reads as "light".
; Returns A=1 if IR light was seen during the window, else A=0.
; Clobbers C.
;------------------------------------------------------------------------
IRSample:
    ldh a, [rRP]
    cpl
    ld c, a
    nop
    nop
    ldh a, [rRP]
    ldh a, [rRP]
    cpl
    or c
    ld c, a
    nop
    ldh a, [rRP]
    ldh a, [rRP]
    cpl
    or c
    srl a
    and $01
    ret

;------------------------------------------------------------------------
; IRWaitSignal - block until IR light is seen, ~3.5s timeout.
; Returns D=0 on timeout, D!=0 if a signal arrived. Clobbers A, B, C.
;------------------------------------------------------------------------
IRWaitSignal:
    ld d, $07
.outer
    ld c, $ff
    call IRWaitSignalC
    ld a, c
    cp $00
    ret nz
    dec d
    jr nz, .outer
    ret

;------------------------------------------------------------------------
; IRWaitSignalC - mid-level wait, up to C polling rounds.
; Returns C!=0 if a signal arrived, C=0 on timeout. Clobbers A, B.
;------------------------------------------------------------------------
IRWaitSignalC:
.loop
    ld b, $ff
    call IRPollSignal
    ld a, b
    cp $00
    ret nz
    dec c
    jr nz, .loop
    ret

;------------------------------------------------------------------------
; IRPollSignal - poll the RP input bit up to B times (input is active-
; low: bit 1 = 0 means IR light present).
; Returns B!=0 if light was seen, B=0 on timeout.
;------------------------------------------------------------------------
IRPollSignal:
.loop
    ldh a, [rRP]
    and $02
    ret z
    dec b
    jr nz, .loop
    ret

;------------------------------------------------------------------------
; IRDelayB - calibrated busy delay, part of the ~100us/unit time base.
;------------------------------------------------------------------------
IRDelayB:
.loop
    dec b
    jr nz, .loop
    ret

;------------------------------------------------------------------------
; IRLearnCore - record up to two frames of mark/space widths into the
; current SRAM bank. Each width is a count of ~100us sampling rounds;
; a space of >=$64 rounds (~9ms+, the inter-frame gap) or a count
; overflow ends the frame. Frame 2 (a protocol's repeat frame) is
; captured if it arrives within the short window after frame 1.
; On timeout or buffer overrun all four buffers are zero-terminated.
; Interrupts are left disabled; caller restores them.
;------------------------------------------------------------------------
IRLearnCore:
    di
    ldh a, [rRP]
    or $c0                    ; enable IR read
    ldh [rRP], a
    call IRWaitSignal
    ld a, d
    cp $00
    jr z, .fail
    ld b, $02                 ; frame countdown (kept on the stack)
    ld de, sMarks1
    ld hl, sSpaces1
    ld c, $7e                 ; entries remaining
    push bc
.pulse
    ld a, $01
    ld [de], a
.markLoop
    call IRSample
    cp $00
    jr z, .spaceStart
    ld a, [de]
    inc a
    ld [de], a
    ld b, $0a
    call IRDelayB
    nop
    nop
    nop
    jr .markLoop
.spaceStart
    ld [hl], $01
.spaceLoop
    call IRSample
    cp $01
    jr z, .pulseEnd
    ld a, [hl]
    inc a
    jr z, .gap                ; space count overflow -> inter-frame gap
    ld [hl], a
    ld b, $0a
    call IRDelayB
    nop
    nop
    jr .spaceLoop
.pulseEnd
    ld a, [hl]
    cp $64
    jr nc, .gap               ; space >= ~9ms -> inter-frame gap
    pop bc
    dec c
    jr z, .fail               ; buffer full
    push bc
    inc hl
    inc de
    jp .pulse
.gap
    inc de
    inc hl
    xor a
    ld [de], a                ; zero-terminate the frame
    ld [hl], a
    pop bc
    dec b
    jr z, .done
    ld de, sMarks2
    ld hl, sSpaces2
    ld c, $7f
    push bc
    ld c, $25                 ; short wait for a repeat frame
    call IRWaitSignalC
    ld a, c
    cp $00
    jp nz, .pulse
    pop bc
    xor a
    ld [sMarks2], a           ; no repeat frame arrived
    ld [sSpaces2], a
    jp .done
.fail
    xor a
    ld [sMarks1], a
    ld [sSpaces1], a
    ld [sMarks2], a
    ld [sSpaces2], a
.done
    ldh a, [rRP]
    and $3f                   ; disable IR read
    ldh [rRP], a
    ret

;------------------------------------------------------------------------
; IRSendFrame - transmit one recorded frame. A = 0 -> frame 1,
; A = 1 -> frame 2. Interrupts are left disabled; caller restores.
; (The original loaded C=$7f here too, but never used it - dropped.)
;------------------------------------------------------------------------
IRSendFrame:
    di
    cp $01
    jr z, .frame2
    ld de, sMarks1
    ld hl, sSpaces1
    jr .entry
.frame2
    ld de, sMarks2
    ld hl, sSpaces2
.entry
    ld a, [de]
    cp $00
    jr z, .done
    ld c, a
    ld a, $01
    call IRPulseUnits         ; mark
    inc de
    ld c, [hl]
    dec c                     ; one unit's worth of loop overhead
    xor a
    call IRPulseUnits         ; space
    ld b, $02
    call IRDelay2
    inc hl
    jr .entry
.done
    ret

;------------------------------------------------------------------------
; IRPulseUnits - drive RP for C units of ~98us each. A=1: mark (LED
; held on ~92% of each unit, off for a short blip). A=0: space (off).
; Same routine gives marks and spaces an identical time base.
;------------------------------------------------------------------------
IRPulseUnits:
    push de
    ld d, a
.unit
    ld b, $0c
.onLoop
    ld a, d
    ldh [rRP], a
    dec b
    jr nz, .onLoop
    xor a
    ldh [rRP], a
    dec c
    jr nz, .unit
    pop de
    ret

;------------------------------------------------------------------------
; IRDelay2 - inter-pulse fixup delay (separate label to mirror the
; original's distinct call target).
;------------------------------------------------------------------------
IRDelay2:
.loop
    dec b
    jr nz, .loop
    ret

;------------------------------------------------------------------------
; IRDelayRepeat - ~130ms between repeated frames while Select is held.
; Not part of the ported timing paths; precision is irrelevant here.
;------------------------------------------------------------------------
IRDelayRepeat:
    ld b, $86
.outer
    ld c, $00
.inner
    dec c
    jr nz, .inner
    dec b
    jr nz, .outer
    ret

;------------------------------------------------------------------------
; IRStampRLEHeader - mark the current SRAM bank as holding a live-learned
; recording. Clears SAVF_RAW: any raw samples in the bank are from a
; different press, and RAW|RLE together must mean "same press".
;------------------------------------------------------------------------
IRStampRLEHeader:
    ld hl, sHdrMagic
    ld a, $49                 ; "I"
    ld [hli], a
    ld a, $52                 ; "R"
    ld [hli], a
    ld a, SAVF_RLE
    ld [hli], a
    ld a, SAV_VERSION
    ld [hli], a
    ld a, IR_UNIT_MCYCLES
    ld [sHdrRleUnit], a
    ld a, $01
    ld [sHdrRleSpeed], a
    ld a, RLESRC_LIVE
    ld [sHdrRleSource], a
    ret

;------------------------------------------------------------------------
; IRConvertRaw - derive a learned code from the raw capture in the
; current bank: the offline equivalent of what IRLearnCore does live.
; Dark runs shorter than CONV_GAP_SAMPLES are carrier chop and get
; absorbed into the surrounding mark (the OR-sampler's job); runs are
; then quantized to IR_UNIT_MCYCLES-sized width units (the sampling
; cadence's job). Frame 2 is always empty - the ~33ms raw window ends
; long before any protocol's repeat frame.
; Returns A=1 on success, A=0 if the capture contains no light at all.
; Offline only - no timing constraints.
;------------------------------------------------------------------------
IRConvertRaw:
    ld hl, sRawSamples
.skipDark
    ld a, h
    cp $c0
    jp z, .fail
    ld a, [hli]
    rra                       ; sample bit 0 -> carry
    jr nc, .skipDark
    dec hl                    ; back up to the first light sample
    ld de, sMarks1
    ld a, $7d
    ld [wConvEntries], a
.pulseLoop
    ld bc, $0000              ; mark length in samples
    xor a
    ld [wConvDark], a
.markLoop
    ld a, h
    cp $c0
    jr z, .eofInMark
    ld a, [hli]
    rra
    jr nc, .darkInMark
    ld a, [wConvDark]         ; light: pending dark was chop, count it
    inc a                     ; as mark along with this sample
    add c
    ld c, a
    ld a, b
    adc 0
    ld b, a
    xor a
    ld [wConvDark], a
    jr .markLoop
.darkInMark
    ld a, [wConvDark]
    inc a
    ld [wConvDark], a
    cp CONV_GAP_SAMPLES
    jr c, .markLoop
    ; dark run too long for chop: the mark ended where it began
    call IRConvDiv
    ld [de], a                ; marks[i]
    ld bc, CONV_GAP_SAMPLES   ; space already CONV_GAP_SAMPLES long
.spaceLoop
    ld a, h
    cp $c0
    jr z, .endOfFrame
    ld a, b
    cp $09                    ; >= 2304 samples ~ 100 units: frame gap
    jr nc, .endOfFrame
    ld a, [hli]
    rra
    jr c, .spaceEnd
    inc bc
    jr .spaceLoop
.spaceEnd
    dec hl                    ; unread the light sample (next mark)
    call IRConvDiv
    call IRConvWriteSpace
    inc de
    ld a, [wConvEntries]
    dec a
    ld [wConvEntries], a
    jr z, .terminate
    jp .pulseLoop
.eofInMark
    call IRConvDiv
    ld [de], a
    ld a, $64                 ; synthesize a frame-gap space
    call IRConvWriteSpace
    jr .terminate
.endOfFrame
    call IRConvDiv
    call IRConvWriteSpace
.terminate
    inc de
    xor a
    ld [de], a                ; terminating mark
    call IRConvWriteSpace     ; terminating space (a = 0)
    xor a
    ld [sMarks2], a           ; frame 2 always empty
    ld [sSpaces2], a
    ld a, $01
    ret
.fail
    xor a
    ld [sMarks1], a
    ld [sSpaces1], a
    ld [sMarks2], a
    ld [sSpaces2], a
    xor a
    ret

;------------------------------------------------------------------------
; IRConvDiv - convert BC raw samples to width units:
; A = clamp(round(BC / CONV_SAMP_PER_UNIT), 1, 255). Clobbers BC.
;------------------------------------------------------------------------
IRConvDiv:
    push de
    ld a, c                   ; BC += half divisor, for rounding
    add (CONV_SAMP_PER_UNIT - 1) / 2
    ld c, a
    ld a, b
    adc 0
    ld b, a
    ld d, 0
.loop
    ld a, c
    sub CONV_SAMP_PER_UNIT
    ld c, a
    ld a, b
    sbc 0
    ld b, a
    jr c, .done
    inc d
    jr nz, .loop
    ld d, $ff                 ; clamp at 255
.done
    ld a, d
    and a
    jr nz, .ok
    inc a                     ; clamp at 1
.ok
    pop de
    ret

;------------------------------------------------------------------------
; IRConvWriteSpace - store A into the space slot parallel to the mark
; slot DE points at (spaces array sits $7F above the marks array).
;------------------------------------------------------------------------
IRConvWriteSpace:
    push hl
    ld c, a
    ld hl, $007f
    add hl, de
    ld [hl], c
    pop hl
    ret

;------------------------------------------------------------------------
; IRLearn - menu entry point for Start. Shows the recording dot, runs
; the learner, stamps the bank header, returns to the menu.
;------------------------------------------------------------------------
IRLearn::
    ld hl, ADDR_SYMBOL_ST
    ld a, REC_SYMBOL_TILENO
    ld [hl], a
    call IRLearnCore
    call IRStampRLEHeader
    call InitInterrupts
    jp MenuLoop

;------------------------------------------------------------------------
; IRSend - menu entry point for Select. Sends frame 1 once; while the
; button is held, keeps sending the repeat frame (frame 2 if recorded,
; else frame 1 again) every ~130ms.
;------------------------------------------------------------------------
IRSend::
    ld hl, ADDR_SYMBOL_SE
    ld a, REC_SYMBOL_TILENO
    ld [hl], a
    xor a
    call IRSendFrame
.holdLoop
    ld a, P1F_GET_BTN
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    bit 2, a
    jr nz, .end               ; Select released
    call IRDelayRepeat
    ld a, [sMarks2]
    cp $00
    jr z, .noRepeatFrame
    ld a, $01
    call IRSendFrame
    jr .holdLoop
.noRepeatFrame
    xor a
    call IRSendFrame
    jr .holdLoop
.end
    xor a
    ldh [rRP], a
    call InitInterrupts
    jp MenuLoop
