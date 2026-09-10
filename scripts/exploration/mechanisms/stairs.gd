## A staircase, ported from the prototype's PlayerController.TryMove.
##
## Detected while MOVING: when the player walks into a staircase's cell, they are carried to
## `position + direction * 2 + floor change` — two cells further, one floor up or down. You
## therefore never land ON the staircase. UpStairs (`level_delta = +1`) and DownStairs
## (`level_delta = -1`) are two cells, bottom and top, making up the same staircase.
##
## The staircase's cell is NOT floor: you do not stop there, you are carried past it.
##
## ## TODO(dungeon checker): the design doc sets two level-design constraints that nothing
## checks — a staircase must lead to floor, normal or special, and the cell DIRECTLY above it
## must be empty. The block of steps rises a full [constant DungeonManager.CELL_SIZE], so a
## floor laid over it would cut straight through without a word. Revisit with the dungeon
## validator, alongside narrow bridges and bottomless holes.
##
## No `class_name`: `extends` by path.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## +1 for stairs going up, -1 for stairs going down.
@export var level_delta := 1
## The horizontal direction the staircase faces, which orients the visual.
@export var face_dir := Vector3i(0, 0, 1)


## Where you land walking into this staircase from `from_cell` along `delta`: two cells further
## plus the floor change, matching the prototype's `pos + dir*2 + up/down`.
func stairs_destination(from_cell: Vector3i, delta: Vector3i) -> Vector3i:
	return from_cell + delta * 2 + Vector3i(0, level_delta, 0)


# --- Floor changes (the common interface; see DungeonMechanism) ---


func has_level_link() -> bool:
	return true


## A staircase is approached from the cell behind it, by walking towards it.
func level_link_from() -> Vector3i:
	return cell - face_dir


func level_link_to() -> Vector3i:
	return stairs_destination(level_link_from(), face_dir)


## A staircase is taken by STEPPING INTO it from the cell in front.
func level_link_needs_step_in() -> bool:
	return true


## How many steps. The prototype used a 6-step ProBuilder "Stairs" shape.
const STEP_COUNT := 6


## The visual: a SOLID BLOCK the size of a cell, cut into steps on its front face — the
## prototype's ProBuilder Stairs 1x1x1, 6 steps, closed sides. Seen from the side or the back it
## is therefore a mass, not a run of floating steps. The first step starts at the cell's EDGE,
## and the last reaches the floor above.
##
## Only the UPWARD cell renders it; the two stacked cells are the same staircase.
func _spawn_visual() -> void:
	if level_delta < 0:
		return
	var hdir := Vector3(face_dir.x, 0.0, face_dir.z)
	if hdir.length() < 0.5:
		hdir = Vector3(0.0, 0.0, 1.0)
	var side := Vector3(absf(hdir.z), 0.0, absf(hdir.x))  # the cross axis, the cell's width
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.62, 0.9)
	var cs := DungeonManager.CELL_SIZE
	var run := cs / float(STEP_COUNT)  # depth of one step
	for i in range(STEP_COUNT):
		# Slice i runs from step i to the next in depth, filled solid from the floor up to its
		# own height — that filling is what makes the block solid.
		var rise := cs * float(i + 1) / float(STEP_COUNT)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = hdir.abs() * run + side * cs + Vector3(0.0, rise, 0.0)
		mi.mesh = box
		mi.material_override = mat
		# The node's origin is the cell's floor at its centre, so start from the edge opposite the
		# climb.
		mi.position = hdir * (-cs * 0.5 + run * (float(i) + 0.5)) + Vector3(0.0, rise * 0.5, 0.0)
		add_child(mi)
