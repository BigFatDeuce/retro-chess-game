class_name Pal
extends RefCounted
## The interface's design tokens: colours, sizes, spacing, durations. Every screen takes its values from here
## ("la planche d'aventure": warm wood rimmed in dark brown, blue rivets, cream letters, leaf green).

# --- colours ---------------------------------------------------------------------------------------------------------
const OUTLINE := Color("2b170c")  ## the dark brown line around everything (as on the logo)
const WOOD_HI := Color("e9a04f")
const WOOD := Color("c0712f")
const WOOD_LO := Color("7e4119")
const WALNUT_HI := Color(0.235, 0.165, 0.11, 0.95)  ## panel body, top
const WALNUT_LO := Color(0.13, 0.09, 0.06, 0.95)  ## panel body, bottom
const CREAM := Color("fdf3dc")
const PARCHMENT := Color("f3e3be")
const PARCHMENT_LO := Color("dcc28e")
const INK := Color("3a2414")  ## text on parchment
const TEXT := Color("fdf3dc")  ## text on wood and walnut
const DIM := Color("cdb690")
const MUTED := Color("8d7a5e")
const GOLD_HI := Color("ffe066")
const GOLD := Color("f5b829")
const GOLD_LO := Color("d97b12")
const LEAF_HI := Color("9be04e")
const LEAF := Color("5fae2c")
const LEAF_LO := Color("2f6e17")
const EMBER_HI := Color("ff8a5c")
const EMBER := Color("e0503a")
const EMBER_LO := Color("962618")
const SKY_HI := Color("9fd3f5")
const SKY := Color("5b9bd1")
const SKY_LO := Color("2d5a8c")
const RIVET := Color("7fb0d6")
const RIVET_LO := Color("2f5677")
const STONE_HI := Color("a9a69c")
const STONE := Color("75736b")
const STONE_LO := Color("45443f")
const SHADOW := Color(0.05, 0.02, 0.0, 0.45)
const VEIL := Color(0.04, 0.03, 0.02, 0.55)

# --- type scale (layout px, the layout being 2560 x 1440 or wider/taller) -----------------------------------------
const FS_HUGE := 132  ## end of game title
const FS_TITLE := 76
const FS_H2 := 54
const FS_BUTTON := 44
const FS_BODY := 34
const FS_SMALL := 28
const FS_TINY := 24

# --- spacing and shapes ----------------------------------------------------------------------------------------------
const S1 := 8
const S2 := 16
const S3 := 24
const S4 := 32
const S5 := 48
const S6 := 64
const RADIUS := 22
const OUTLINE_W := 5.0
const EDGE := 32  ## distance kept from the screen edges

# --- motion ----------------------------------------------------------------------------------------------------------
const T_FAST := 0.12
const T_MED := 0.22
const T_SLOW := 0.45


## True on phones and tablets: larger touch targets, no keyboard hints.
static func touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## A duration, or nearly none when the player asked for fewer animations.
static func dur(t: float) -> float:
	return 0.001 if reduced_motion() else t


static func reduced_motion() -> bool:
	return bool(Settings.get_value("reduce_motion"))


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
