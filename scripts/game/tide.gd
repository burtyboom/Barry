class_name Tide
extends RefCounted
## Sea level that rises and falls like the real thing: two highs and two lows a day
## (semi-diurnal, 12 h 25 min cycle), so it takes about 6 h to go from high to low.
##
## By default it follows the real clock, so playing at different times of day gives
## different beach access. The admin menu can pin it to a phase for testing
## (synced to everyone in a multiplayer game).
##
## phase: 0 = high tide, 0.25 = mid (falling), 0.5 = low tide, 0.75 = mid (rising).

const PERIOD := 12.42 * 3600.0     ## seconds from one high tide to the next
const AMPLITUDE := 0.75            ## metres above / below mean sea level (1.5 m range)
const EPOCH_OFFSET := 0.31         ## shifts which clock time is high tide

static var level := 0.0            ## current sea level (m), mean = 0
static var override_phase := -1.0  ## >= 0: pinned by the admin menu


static func real_phase() -> float:
	return fposmod(Time.get_unix_time_from_system() / PERIOD + EPOCH_OFFSET, 1.0)


static func phase() -> float:
	return override_phase if override_phase >= 0.0 else real_phase()


static func level_at_phase(ph: float) -> float:
	return AMPLITUDE * cos(TAU * ph)


static func update() -> void:
	level = level_at_phase(phase())


## Short human description, e.g. "Low tide, rising - high in 5 h 40 m".
static func describe() -> String:
	var ph := phase()
	var label := ""
	if ph < 0.08 or ph > 0.92:
		label = "High tide"
	elif ph > 0.42 and ph < 0.58:
		label = "Low tide"
	elif ph < 0.5:
		label = "Tide falling"
	else:
		label = "Tide rising"
	var next_is_high := ph >= 0.5
	var to_go := ((1.0 - ph) if next_is_high else (0.5 - ph)) * PERIOD
	var h := int(to_go / 3600.0)
	var m := int(fmod(to_go, 3600.0) / 60.0)
	var pinned := "  (pinned)" if override_phase >= 0.0 else ""
	return "%s %+.1f m - %s in %dh %02dm%s" % [label, level, "high" if next_is_high else "low", h, m, pinned]
