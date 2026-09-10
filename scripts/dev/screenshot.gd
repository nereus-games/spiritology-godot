## Screenshot of an exploration scenario without going through the editor — a quick visual check
## on scale, walls and gateways from the command line.
##
## Run with: Godot --path . res://scenes/dev/screenshot.tscn -- <scenario> <path.png> [view]
## `view` is optional:
##   - `top`        : an overhead camera instead of the first-person view;
##   - `x,y,z@yaw`  : first place the player on that tile, turned `yaw` degrees (0 faces -z),
##                    then capture their first-person view.
## No --headless: a rendering context is needed, so a window opens briefly.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id: StringName = StringName(args[0]) if args.size() > 0 else &"gates"
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	ScenarioCatalog.selected_id = id
	await get_tree().process_frame  # let the root finish installing its children
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	for i in range(30):
		await get_tree().process_frame
	var pl = scene.get_node("Player")
	var view: String = args[2] if args.size() > 2 else ""
	if "@" in view:
		var parts := view.split("@")
		var xyz := parts[0].split(",")
		pl.teleport_to(Vector3i(int(xyz[0]), int(xyz[1]), int(xyz[2])))
		pl.set_start_yaw(deg_to_rad(float(parts[1])))
		await get_tree().process_frame
	var cam: Camera3D = pl.get_node("CameraRig/Camera3D")
	print(
		(
			"[shot] player %s tile=%s yaw=%.0f deg | camera %s looking at %s | current=%s fov=%.0f"
			% [
				pl.global_position,
				pl.tile,
				rad_to_deg(pl.rotation.y),
				cam.global_position,
				-cam.global_transform.basis.z,
				cam.current,
				cam.fov
			]
		)
	)
	if view == "top":
		var top := Camera3D.new()
		scene.add_child(top)
		top.global_position = pl.global_position + Vector3(0.0, 8.0, 4.0)
		# Aim at the player rather than at the point straight below the camera: a vertical aim is
		# collinear with the up vector, and lets `look_at` pick an arbitrary rotation around Z.
		top.look_at(pl.global_position, Vector3.UP)
		top.current = true
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[shot] %s -> %s" % [id, out])
	get_tree().quit()
