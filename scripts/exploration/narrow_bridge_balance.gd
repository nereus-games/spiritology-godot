## Modèle d'équilibre d'un pont étroit (test d'équilibre temps réel).
##
## Doc Notion (Level Design / Mechanisms « Narrow Bridges »). Une fois engagé sur un pont,
## le personnage avance TOUT SEUL ; le joueur doit corriger en temps réel par des mouvements
## latéraux pour rester en équilibre. Le déséquilibre est proportionnel au score PSY ; sous
## l'effet du piège disarray, l'inertie latérale augmente (correction moins réactive).
##
## Trois façons de tomber, voulues :
##   - ne rien faire : le pendule inversé diverge tout seul ;
##   - corriger TROP PEU / TROP TARD : une bourrasque non contrée pousse hors de la planche ;
##   - corriger TROP : la latence humaine + l'inertie de commande transforment la
##     surcorrection en oscillation divergente.
##
## Le test est CONTINU sur toute la traversée : `imbalance` ET `lateral_velocity` sont
## conservés d'une case à l'autre (cf. [method restart_cell]) — c'est l'inertie du personnage.
## Seule `progress` repart à 0 à chaque case.
##
## Ce script est la LOGIQUE PURE (sans entrée ni rendu), pilotée image par image par
## [method tick] : le pilote temps réel (entrée latérale + animation d'avance + caméra) se
## branchera dessus en moteur. Séparé pour être testable headless.
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`.
extends RefCounted

## Seuil de chute : |imbalance| >= ce seuil = le personnage tombe.
const FALL_THRESHOLD := 1.0

## Inertie de BASE de la commande latérale : constante de temps (s) que met l'entrée du
## joueur à s'établir ET à retomber. C'est le référent du « X % d'inertie en plus » de la doc
## — sans elle, « +X % » n'aurait pas de base à laquelle s'ajouter.
const COMMAND_INERTIA := 0.10

## Inertie AJOUTÉE par le piège disarray, en fraction de [constant COMMAND_INERTIA]
## (doc : « adding X % more inertia to lateral movements »).
##
## Calé à +25 % : mesuré sur 1500 traversées, ça fait passer un joueur normal de 12,5 % à
## 16,3 % de chutes à PSY 0, et de 27,7 % à 32,9 % à PSY 20 — soit un tiers de risque en plus,
## perceptible sans rendre le pont infranchissable une fois cumulé à un PSY élevé.
const DISARRAY_INERTIA := 0.25

## Temps d'établissement d'une bourrasque (s) : au-delà, elle est franche, pas un bruit.
const GUST_SMOOTH := 0.35
## Durée de vie d'une bourrasque avant tirage de la suivante (s).
const GUST_MIN_PERIOD := 0.5
const GUST_MAX_PERIOD := 1.4

## Déséquilibre courant dans [-∞, +∞] mais borné par la chute (négatif = penche d'un côté,
## positif = de l'autre).
var imbalance := 0.0
## Vitesse latérale courante (intégrée dans `imbalance`). CONSERVÉE d'une case à l'autre.
var lateral_velocity := 0.0
## Avancement le long de la case courante, 0 → 1 (le personnage avance seul).
var progress := 0.0

# --- Paramètres (calés par balayage, cf. commentaires de valeurs cibles) ---
## Instabilité type « pendule inversé » : plus on penche, plus on tombe vite. C'est ce qui
## OBLIGE à rétablir l'équilibre — sans correction, le déséquilibre diverge et on tombe.
var instability := 1.2
## Amplitude de base des bourrasques (indépendante du PSY). Volontairement du même ordre que
## [member input_strength] : une bourrasque non contrée fait tomber, mais reste contrable.
var base_perturbation := 0.9
## Amplitude supplémentaire par point de PSY (déséquilibre ∝ PSY). Faible : au-delà,
## la bourrasque dépasse la correction et le pont devient infranchissable à haut PSY.
var perturbation_per_psy := 0.008
## Efficacité de la correction latérale (A/D) : agit sur la vitesse pour contrer la chute.
var input_strength := 1.2
## Progression par seconde le long de la case (dérivée de la longueur dans [method configure]).
var forward_speed := 0.5
## Durée d'une case du pont, en secondes. Le personnage avance seul, à pas prudents.
var seconds_per_cell := 2.0
## Friction (proportionnelle) sur la vitesse latérale. Par seconde.
var friction := 0.8
## Inertie ajoutée par le disarray, en fraction de [constant COMMAND_INERTIA] : >0 rend la
## commande plus lente à s'établir ET à retomber (doc).
var disarray_inertia := 0.0

var _amplitude := 0.9
## Bourrasque courante et sa cible (la courante rejoint la cible en [constant GUST_SMOOTH]).
var _gust := 0.0
var _gust_target := 0.0
var _gust_timer := 0.0
## Commande latérale RÉELLEMENT appliquée : suit l'entrée du joueur avec l'inertie de commande.
var _applied_input := 0.0
var _fallen := false
var _rng := RandomNumberGenerator.new()


## `seed_value >= 0` rend les perturbations déterministes (tests).
func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_gust_timer = _rng.randf_range(GUST_MIN_PERIOD, GUST_MAX_PERIOD)


## Configure le test selon le score PSY, la longueur d'une case (toujours 1 : le test est
## continu, chaque case est un segment) et l'état disarray.
func configure(psy_score: int, length: int = 1, disarrayed: bool = false) -> void:
	_amplitude = base_perturbation + maxi(psy_score, 0) * perturbation_per_psy
	forward_speed = 1.0 / (maxf(float(length), 1.0) * seconds_per_cell)
	disarray_inertia = DISARRAY_INERTIA if disarrayed else 0.0


## Case franchie : on repart pour la suivante SANS remettre l'équilibre à plat. Le
## déséquilibre, la vitesse latérale, la bourrasque en cours et la commande déjà engagée
## sont conservés — sinon chaque bord de case effacerait l'élan (anti-inertie).
func restart_cell() -> void:
	progress = 0.0


## Avance d'un pas de temps. `lateral_input` ∈ [-1, 1] = correction latérale du joueur.
func tick(delta: float, lateral_input: float) -> void:
	if _fallen or is_complete():
		return
	# Bourrasque CORRÉLÉE : elle s'installe, dure ~1 s, puis change. Contrairement à un bruit
	# blanc (qui s'annule en s'intégrant), elle pousse vraiment — c'est elle qui punit la
	# sous-correction.
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		_gust_target = _rng.randf_range(-1.0, 1.0) * _amplitude
		_gust_timer = _rng.randf_range(GUST_MIN_PERIOD, GUST_MAX_PERIOD)
	_gust = lerpf(_gust, _gust_target, minf(1.0, delta / GUST_SMOOTH))
	# Inertie de commande : l'entrée met du temps à s'établir ET à retomber. Le disarray
	# allonge cette constante de temps — la correction arrive en retard, donc dépasse.
	var tau := COMMAND_INERTIA * (1.0 + disarray_inertia)
	_applied_input = lerpf(_applied_input, clampf(lateral_input, -1.0, 1.0), minf(1.0, delta / tau))
	# Pendule inversé : plus on est penché, plus la vitesse de chute augmente (instable).
	lateral_velocity += imbalance * instability * delta
	lateral_velocity += _gust * delta
	lateral_velocity += _applied_input * input_strength * delta
	# Friction proportionnelle (douce) : amortit sans annuler les petites vitesses (sinon
	# l'instabilité ne pourrait jamais diverger).
	lateral_velocity *= maxf(0.0, 1.0 - friction * delta)
	imbalance += lateral_velocity * delta
	# Avancée automatique, légèrement saccadée (on tient en équilibre sur un support étroit).
	progress += forward_speed * delta * _rng.randf_range(0.75, 1.25)
	if absf(imbalance) >= FALL_THRESHOLD:
		_fallen = true


func is_fallen() -> bool:
	return _fallen


func is_complete() -> bool:
	return progress >= 1.0 and not _fallen


## En cours = engagé, ni tombé ni arrivé.
func is_active() -> bool:
	return not _fallen and not is_complete()
