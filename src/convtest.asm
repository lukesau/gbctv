SECTION "Conversion Test", ROM0
;------------------------------------------------------------------------
; Emulator-only harness, assembled with rgbasm -DCONVTEST. Fills the raw
; buffer with a synthetic capture (NEC-ish header, a chopped mark, a
; frame gap), runs the real IRConvertRaw, and prints marks1[0..3] and
; spaces1[0..3] as hex so a screenshot verifies the conversion.
; Expected: 09 02 01 00 / 05 02 64 00.
;------------------------------------------------------------------------
ConvTest::
    ; All-dark raw buffer
    ld hl, sRawSamples
.clear
    xor a
    ld [hli], a
    ld a, h
    cp $c0
    jr nz, .clear

    ; Write (count16, value) runs from the pattern table
    ld hl, sRawSamples
    ld de, .pattern
.runLoop
    ld a, [de]
    ld c, a
    inc de
    ld a, [de]
    ld b, a
    inc de
    ld a, b
    or c
    jr z, .patEnd
    ld a, [de]
    inc de
    push de
    ld d, a
.fill
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .fill
    pop de
    jr .runLoop
.patEnd

    call IRConvertRaw

    ld de, sMarks1
    ld hl, $99E1              ; row 15
    call .print4
    ld de, sSpaces1
    ld hl, $9A01              ; row 16
.print4
    ld b, $04
.p4
    ld a, [de]
    inc de
    push de
    ld d, a
    swap a
    call NibbleToASCII
    ld [hli], a
    ld a, d
    call NibbleToASCII
    ld [hli], a
    inc hl
    pop de
    dec b
    jr nz, .p4
    ret

.pattern
    dw 210
    db 1                      ; ~900us mark -> 9 units
    dw 105
    db 0                      ; ~450us space -> 5 units
    dw 10
    db 1                      ; chopped mark: 10 light, 5 dark, 10, 5, 10
    dw 5
    db 0                      ;   -> merges to 40 samples -> 2 units
    dw 10
    db 1
    dw 5
    db 0
    dw 10
    db 1
    dw 40
    db 0                      ; ~170us space -> 2 units
    dw 23
    db 1                      ; one-unit mark
    dw 2400
    db 0                      ; frame gap -> space $64, frame ends
    dw 0
