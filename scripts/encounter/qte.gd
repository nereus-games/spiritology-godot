## The quick-time event behind Slick Merchant's Run Away: the pure rules, with no node and no
## clock of its own, so that they can be checked headless.
##
## The doc says only that Run Away is "behind a QTE" that can fail; the form is ours. A marker
## sweeps along a bar from 0 to 1 and back (a triangle wave over time), and the player presses
## Accept once. The press succeeds when the marker is inside the zone at that moment; a press
## outside it fails, and so does no press before the time limit. The figures are in
## `data/balance.tres` (`qte_*`), all placeholders.
##
## Whoever plays it (the encounter UI's overlay) owns the clock and feeds [method evaluate] the
## time of the press; whoever does not play it (a check, a rival) never builds one. The manager
## reaches it only through [member EncounterManager.qte_runner].
##
## No `class_name`, see CLAUDE.md: preloaded.
extends RefCounted

enum Outcome { HIT, MISS, TIMEOUT }

var period := 1.2
var zone_center := 0.5
var zone_width := 0.3
var time_limit := 3.0


## A QTE with the figures of `data/balance.tres`.
static func from_balance():
	var b := BalanceData.current()
	var q = new()
	q.period = b.qte_period
	q.zone_center = b.qte_zone_center
	q.zone_width = b.qte_zone_width
	q.time_limit = b.qte_time_limit
	return q


## Where the marker is, 0 to 1, `seconds` after the QTE began. It starts at 0, reaches 1 after half
## a period and comes back.
func marker_at(seconds: float) -> float:
	var phase := fposmod(seconds / period, 1.0)
	return 1.0 - absf(2.0 * phase - 1.0)


## Whether a marker at `position` is inside the zone, its edges included.
func in_zone(position: float) -> bool:
	return absf(position - zone_center) <= zone_width / 2.0 + 0.000001


## What a press `seconds` after the start comes to. A negative time, or the limit reached or
## passed, is a [constant Outcome.TIMEOUT]; pass [constant INF] for "never pressed".
func evaluate(seconds: float) -> Outcome:
	if seconds < 0.0 or seconds >= time_limit:
		return Outcome.TIMEOUT
	return Outcome.HIT if in_zone(marker_at(seconds)) else Outcome.MISS


static func succeeded(outcome: Outcome) -> bool:
	return outcome == Outcome.HIT
