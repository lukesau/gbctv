SECTION "Font", ROM0
FontTiles:
INCBIN "inc/font.chr"
FontTilesEnd:

SECTION "Strings", ROM0
strNonCGB_L1: db "  This program is  ", 0
strNonCGB_L2: db "Gameboy Color Only!", 0
strTitle: db "GBCTV IR Lab", 0
strPressA: db "(A) Raw Capture", 0
strPressB: db "(B) Raw Replay", 0
strPressStart: db "(STA) Learn Code", 0
strPressSelect: db "(SEL) Send Code", 0
strProfile: db "Profile: < 0 >", 0