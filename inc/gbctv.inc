; VRAM Addresses
DEF ADDR_TITLE_LABEL      EQU $9822
DEF ADDR_REC_LABEL        EQU $98A1
DEF ADDR_PLAY_LABEL       EQU $98E1
DEF ADDR_SYMBOL_A         EQU $98A2
DEF ADDR_SYMBOL_B         EQU $98E2
DEF ADDR_LEARN_LABEL      EQU $9921
DEF ADDR_SEND_LABEL       EQU $9961
DEF ADDR_SYMBOL_ST        EQU $9932
DEF ADDR_SYMBOL_SE        EQU $9972
DEF ADDR_PROFILE_LABEL    EQU $99A3
DEF ADDR_SYMBOL_PNUM      EQU $99AE
DEF ADDR_NON_CGB_LABEL_L1 EQU $98C1
DEF ADDR_NON_CGB_LABEL_L2 EQU $98E1

; Display-related constants
DEF REC_SYMBOL_TILENO EQU $1F

; Program-specific constants
DEF MAX_PROFILE_NO   EQU $0F
DEF PSWITCH_COOLDOWN EQU $0A

; SRAM bank header (see src/ram.asm and tools/parse_sav.py)
DEF SAVF_RAW EQU $01        ; bank holds valid raw RP samples
DEF SAVF_RLE EQU $02        ; bank holds valid mark/space width arrays
DEF SAV_VERSION EQU $01
DEF RLESRC_LIVE    EQU $01  ; learned live by the Start-button recorder
DEF RLESRC_DERIVED EQU $02  ; converted from this bank's raw capture

; Timing metadata values (normal-speed M-cycles unless noted)
DEF IR_UNIT_MCYCLES  EQU 105 ; learned-mode width unit (~100us)
DEF RAW_PERIOD_MCYC  EQU 9   ; raw sample period, in DOUBLE-speed M-cycles (~4.3us)

; Raw -> learned conversion (IRConvertRaw)
DEF CONV_GAP_SAMPLES EQU 16  ; dark run shorter than this (~69us) = carrier
                             ; chop inside a mark, not a real space
DEF CONV_SAMP_PER_UNIT EQU 23 ; raw samples per width unit
                             ; (105 normal M-cyc = 210 double = 210/9 = 23.3)
