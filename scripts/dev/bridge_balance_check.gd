## Vérification headless du MODÈLE d'équilibre du pont étroit ([NarrowBridgeBalance]).
##
## Le calage du pont ne se juge pas à l'œil : on simule des milliers de traversées avec des
## « joueurs » virtuels de qualité croissante et on vérifie que le taux de chute reste dans la
## bande visée. C'est ce qui protège le calage d'une régression silencieuse.
##
## Contrat de design vérifié ici :
##   - ne rien faire      -> on tombe (le pendule inversé diverge) ;
##   - corriger trop peu  -> on tombe souvent (les bourrasques poussent hors de la planche) ;
##   - corriger normalement -> on passe la plupart du temps ;
##   - corriger en anticipant -> on passe ;
##   - le PSY durcit le test, le disarray aussi.
##
## Lancé par : Godot --headless --path . res://scenes/dev/bridge_balance_check.tscn
## (scène de démarrage, et non --script : cf. geometry_check.gd.)
extends Node

const NarrowBridgeBalance := preload("res://scripts/exploration/narrow_bridge_balance.gd")

## Pas de temps simulé (60 Hz) et longueur du pont de référence.
const DT := 1.0 / 60.0
const CELLS := 5
const RUNS := 1500

var _fails: Array[String] = []

## Profils de « joueur » : latence de réaction (s), anticipation de la vitesse (s) et zone
## morte (au-dessous, le joueur ne corrige pas). `passive` = ne touche à rien.
const PROFILES := {
	"passif": {"reaction": 999.0, "lookahead": 0.0, "deadzone": 0.0, "passive": true},
	"mou": {"reaction": 0.35, "lookahead": 0.0, "deadzone": 0.35, "passive": false},
	"normal": {"reaction": 0.25, "lookahead": 0.12, "deadzone": 0.08, "passive": false},
	"attentif": {"reaction": 0.18, "lookahead": 0.25, "deadzone": 0.05, "passive": false},
}


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	print("Pont de %d cases, %d traversées par mesure.\n" % [CELLS, RUNS])

	print("[taux de chute selon le joueur — PSY 0, sans disarray]")
	var base := {}
	for name in PROFILES:
		base[name] = _fall_rate(name, 0, false)
		print("  %-9s %5.1f %%" % [name, base[name]])
	_check(base["passif"] > 95.0, "ne rien faire fait tomber (%.1f %%)" % base["passif"])
	_check(base["mou"] > 45.0, "corriger trop peu fait tomber souvent (%.1f %%)" % base["mou"])
	_check(
		base["normal"] > 3.0 and base["normal"] < 30.0,
		"un joueur normal passe le plus souvent, sans que ce soit acquis (%.1f %%)" % base["normal"]
	)
	_check(base["attentif"] < 5.0, "anticiper suffit à traverser (%.1f %%)" % base["attentif"])
	_check(
		base["mou"] > base["normal"] and base["normal"] > base["attentif"],
		"le taux de chute décroît strictement avec la qualité du jeu"
	)

	print("\n[effet du PSY — joueur normal, sans disarray]")
	var psy_rates := []
	for psy in [0, 10, 20, 30, 40]:
		var r := _fall_rate("normal", psy, false)
		psy_rates.append(r)
		print("  PSY %-3d %5.1f %%" % [psy, r])
	_check(
		psy_rates[4] > psy_rates[0] + 10.0,
		"un PSY élevé durcit nettement le test (%.1f %% -> %.1f %%)" % [psy_rates[0], psy_rates[4]]
	)
	_check(
		psy_rates[4] < 85.0,
		"un PSY élevé ne rend pas le pont infranchissable (%.1f %%)" % psy_rates[4]
	)

	print(
		(
			"\n[effet du disarray — inertie de commande +%.0f %%]"
			% (NarrowBridgeBalance.DISARRAY_INERTIA * 100.0)
		)
	)
	for psy in [0, 20]:
		var clean := _fall_rate("normal", psy, false)
		var dis := _fall_rate("normal", psy, true)
		print("  PSY %-3d %5.1f %%  ->  %5.1f %% sous disarray" % [psy, clean, dis])
		_check(
			dis > clean,
			"PSY %d : le disarray rend le test plus dur (%.1f -> %.1f %%)" % [psy, clean, dis]
		)

	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## Taux de chute (%) sur [constant RUNS] traversées complètes.
func _fall_rate(profile: String, psy: int, disarrayed: bool) -> float:
	var fell := 0
	for i in range(RUNS):
		if not _cross(profile, psy, disarrayed, i):
			fell += 1
	return 100.0 * float(fell) / float(RUNS)


## Une traversée complète : [constant CELLS] cases enchaînées sur le MÊME modèle (le
## déséquilibre et la vitesse latérale traversent les bords de case). Retourne `true` si
## le joueur simulé arrive de l'autre côté.
func _cross(profile: String, psy: int, disarrayed: bool, seed_value: int) -> bool:
	var p: Dictionary = PROFILES[profile]
	var bal = NarrowBridgeBalance.new(seed_value)
	bal.configure(psy, 1, disarrayed)
	var input := 0.0
	var since := 0.0
	for _cell in range(CELLS):
		bal.restart_cell()
		while not bal.is_complete():
			if not p["passive"]:
				since += DT
				if since >= p["reaction"]:
					since = 0.0
					# Le joueur vise le centre d'après ce qu'il VOIT (roulis) et, s'il est bon,
					# d'après la vitesse à laquelle ça part.
					var seen: float = bal.imbalance + p["lookahead"] * bal.lateral_velocity
					input = 0.0 if absf(seen) < p["deadzone"] else (-1.0 if seen > 0.0 else 1.0)
			bal.tick(DT, input)
			if bal.is_fallen():
				return false
	return true
