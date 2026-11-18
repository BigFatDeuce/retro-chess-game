class_name FreePlay
## Free play, open from the start beside the champions' path: any board, any strength from MIN_ELO to MAX_ELO.
## From UCI_MIN the engine's own limited-strength mode (UCI_Elo); below, where the engine cannot weaken itself, the
## human-like model (HumanMind, docs/HUMAN_AI.md), measured on the same scale against UCI_Elo 1350.
## A free game is not part of the path: it opens nothing and is not counted in a champion's record.

const ID := "free"
const MIN_ELO := 600  ## the bottom of HumanMind.TABLE
const MAX_ELO := 2800  ## the engine's UCI_Elo ceiling is 2850
const STEP := 50
const UCI_MIN := 1350  ## the engine's UCI_Elo floor


## Engine settings for a strength (see the class comment).
static func engine_for(elo: int) -> Dictionary:
	elo = clampi(elo, MIN_ELO, MAX_ELO)
	if elo >= UCI_MIN:
		return {"uci_elo": elo, "movetime": 400}
	return {"human": elo}


## The champion closest in strength (their portrait stands for the free opponent).
static func nearest(elo: int) -> Dictionary:
	var best: Dictionary = {}
	for o: Dictionary in Profiles.opponents:
		if best.is_empty() or absi(int(o["elo"]) - elo) < absi(int(best["elo"]) - elo):
			best = o
	return best


## An opponent dictionary for the game and the HUD, like the champions' (data/opponents.json).
static func opponent(elo: int, board: String) -> Dictionary:
	var n := nearest(elo)
	return {"id": ID, "name": "Adversaire libre", "elo": elo, "measured": true, "board": board,
		"engine": engine_for(elo), "avatar": String(n.get("avatar", "tofu")), "free": true}
