extends CharacterBody3D
## Based on Garbaj's ideas in his awesome FPS controller for Godot 3
## https://github.com/GarbajYT/godot_updated_fps_controller

## Crosshair by the awesome Kenney
## https://www.kenney.nl/assets/crosshair-pack

## Prototype textures also by Kenney
## https://www.kenney.nl/assets/prototype-textures

## The code is very "prototypey" as of now

## Jump and Land sounds aren't included

var speed: float = 15
const ACCEL_DEFAULT: float = 7
const ACCEL_AIR: float = 1
var gravity: float = 9.8
var jump: float = 8

var cam_accel: float = 40
var mouse_sense: float = 0.1
var pad_sense: float = 1.5
var snap

# Current stamina
var stamina: float = 100.0

# How fast the stamina decays
# Set to 0.0 for infinite stamina or just strip code parts
var stamina_decay_rate: float = 30.0

# How long the player is wallrunning
var wallrun_time: float = 0.0

# Max time the player can wallrun
var MAX_WALLRUN_TIME: float = 2.0

# Can the player jump a second time?
var double_jump: bool = true

# Is the player going to land now?
var landing: bool = false

# Is the player crouching now?
var crouching: bool = false


var direction: Vector3 = Vector3()
var velocity: Vector3 = Vector3()
var gravity_vec: Vector3 = Vector3()
var movement: Vector3 = Vector3()

@onready var accel = ACCEL_DEFAULT
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var bobbing_anim: AnimationPlayer = $Head/Camera3D/Bobbing
@onready var shaking_anim: AnimationPlayer = $Head/Camera3D/Shaking

# The curve for the wallrun for a nice arc motion
@export var wallrun_curve: Curve


func _ready():
	# Capture the mouse at the start of the game
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event):
	# Move the camera with mouse motion
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * mouse_sense))
		head.rotate_x(deg2rad(-event.relative.y * mouse_sense))
		head.rotation.x = clamp(head.rotation.x, deg2rad(-85), deg2rad(85))
	
	# Capture the mouse on click
	elif event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Make the mouse visible on pressing ESC
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta):
	# Some magic for high refresh rate monitors
	if Engine.get_frames_per_second() > Engine.get_physics_ticks_per_second():
		camera.set_as_top_level(true)
		camera.global_transform.origin = camera.global_transform.origin.lerp(head.global_transform.origin, cam_accel * delta)
		camera.rotation.y = rotation.y
		camera.rotation.x = head.rotation.x
	else:
		camera.set_as_top_level(false)
		camera.global_transform.origin = head.global_transform.origin
	
	# Dynamic camera FOV based on character speed; sense of speed
	camera.fov = lerp(camera.fov, 75 + motion_velocity.length(), 0.1)
	
	# Rotating around with gamepad
	if InputEventJoypadMotion:
		var axis_vector = Vector2.ZERO
		
		axis_vector.x = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		axis_vector.y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		
		rotate_y(deg2rad(-axis_vector.x * pad_sense))
		head.rotate_x(deg2rad(-axis_vector.y * pad_sense))
		head.rotation.x = clamp(head.rotation.x, deg2rad(-85), deg2rad(85))
	
	# Lerp the Stamina Bar
	$HUD/StaminaBar.value = lerp($HUD/StaminaBar.value, stamina, 0.1)


func _physics_process(delta):
	direction = Vector3.ZERO
	var h_rot = global_transform.basis.get_euler().y
	var f_input = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	var h_input = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction = Vector3(h_input, 0, f_input).rotated(Vector3.UP, h_rot).normalized()
	
	if is_on_floor():
		# If the player just landed
		if landing:
			landing = false
			spawn_jump_particles()
			
			$Sounds/Land.stop()
			$Sounds/Land.play()
			bobbing_anim.stop()
			bobbing_anim.play("gigabob_down")
			snap = -get_floor_normal()
			accel = ACCEL_DEFAULT
			double_jump = true
			stamina = 100.0
			wallrun_time = 0
			if camera.rotation.z != 0.0:
				var head_tween: Tween = get_tree().create_tween()
				head_tween.tween_property(camera, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC)
		
		gravity_vec = Vector3.ZERO
	else:
		if not landing:
			landing = true
		snap = Vector3.DOWN
		accel = ACCEL_AIR
		gravity_vec += Vector3.DOWN * gravity * delta
	
	# Jump
	if Input.is_action_just_pressed("jump"):
		# Jump from the ground
		if is_on_floor():
			gravity_vec = Vector3.UP * jump + get_platform_velocity()
			spawn_jump_particles()
			
			play_jump_sound(0.3, 0.5)
		
		# Double jump if the player is not on a wall
		elif double_jump and not ($LeftWallRay.is_colliding() or $RightWallRay.is_colliding()):
			double_jump = false
			gravity_vec = Vector3.UP * jump
			var forward_dir = Vector3.FORWARD.rotated(Vector3.UP, h_rot).normalized()
			velocity = forward_dir * 20
			spawn_jump_particles()
			
			play_jump_sound(0.5, 0.7)
		
		# Mantle a wall
		else:
			if not $MantleRays/TopRay.is_colliding():
				if $MantleRays/MidRay.is_colliding():
					gravity_vec = Vector3.UP * jump * 1.1
				elif $MantleRays/BottomRay.is_colliding():
					gravity_vec = Vector3.UP * jump * 0.8
	
	# Holding jump to wallrun
	if Input.is_action_pressed("jump"):
		if stamina <= 0 or wallrun_time >= MAX_WALLRUN_TIME:
			pass
		
		# The wall is on the left side of the player
		elif $LeftWallRay.is_colliding():
			if wallrun_time == 0:
				var head_tween: Tween = get_tree().create_tween()
				head_tween.tween_property(camera, "rotation:z", -0.15, 0.3).set_trans(Tween.TRANS_CUBIC)
			double_jump = true
			wallrun_time += delta
			gravity_vec = wallrun_curve.interpolate(wallrun_time/MAX_WALLRUN_TIME) * 5 * Vector3.UP
			stamina -= delta * stamina_decay_rate
			direction = direction.slide($LeftWallRay.get_collision_normal())
			direction -= $LeftWallRay.get_collision_normal()
		
		# The wall is on the right side of the player
		elif $RightWallRay.is_colliding():
			if wallrun_time == 0:
				var head_tween: Tween = get_tree().create_tween()
				head_tween.tween_property(camera, "rotation:z", 0.15, 0.3).set_trans(Tween.TRANS_CUBIC)
			double_jump = true
			wallrun_time += delta
			gravity_vec = wallrun_curve.interpolate(wallrun_time/MAX_WALLRUN_TIME) * 5 * Vector3.UP
			stamina -= delta * stamina_decay_rate
			direction = direction.slide($RightWallRay.get_collision_normal())
			direction -= $RightWallRay.get_collision_normal()
		
		# Vertical wallrun
		elif $FrontWallRay.is_colliding():
			double_jump = true
			gravity_vec = Vector3.UP * 8
			stamina -= delta * stamina_decay_rate
			# Final boost at the top of the wall
			if not $MantleRays/TopRay.is_colliding():
				gravity_vec = Vector3.UP * jump * 1.1
	
	# Letting go of the jump
	if Input.is_action_just_released("jump"):
		# Get the looking dir to boost the player forward
		var forward_dir = Vector3.FORWARD.rotated(Vector3.UP, h_rot).normalized()
		if stamina <= 0:
			pass
		
		# The wall was on the left side of the player
		elif $LeftWallRay.is_colliding():
			gravity_vec = Vector3.UP * jump
			velocity = forward_dir * 20
			stamina -= 30
			var head_tween: Tween = get_tree().create_tween()
			head_tween.tween_property(camera, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC)
			wallrun_time = 0
			spawn_jump_particles()
			
			play_jump_sound(0.3, 0.5)
		
		# The wall was on the right side of the player
		elif $RightWallRay.is_colliding():
			gravity_vec = Vector3.UP * jump
			velocity = forward_dir * 20
			stamina -= 30
			var head_tween: Tween = get_tree().create_tween()
			head_tween.tween_property(camera, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC)
			wallrun_time = 0
			spawn_jump_particles()
			
			play_jump_sound(0.3, 0.5)
		
		elif $FrontWallRay.is_colliding():
			if not $MantleRays/TopRay.is_colliding():
				gravity_vec = Vector3.UP * jump * 1.5
			else:
				gravity_vec = Vector3.UP * jump
				velocity = -forward_dir * 20
				stamina -= 30
			spawn_jump_particles()
			
			play_jump_sound(0.3, 0.5)
	
	
	# Wonky crouching
	if Input.is_action_pressed("crouch") and not crouching:
		var head_crouch_tween: Tween = get_tree().create_tween()
		head_crouch_tween.tween_property($Head, "position:y", -0.45, 0.5).set_trans(Tween.TRANS_CUBIC)
		crouching = true
		$Capsule.disabled = true
		$CapsuleCrouch.disabled = false
	
	if Input.is_action_just_released("crouch") and crouching:
		var head_crouch_tween: Tween = get_tree().create_tween()
		head_crouch_tween.tween_property($Head, "position:y", 1.89, 0.5).set_trans(Tween.TRANS_CUBIC)
		crouching = false
		$Capsule.disabled = false
		$CapsuleCrouch.disabled = true
	
	velocity = velocity.lerp(direction * speed, accel * delta)
	movement = velocity + gravity_vec
	
	if bobbing_anim.get_current_animation() != "gigabob_down":
		if direction != Vector3.ZERO:
			bobbing_anim.play("bobbing")
		elif bobbing_anim.is_playing():
			bobbing_anim.play("chill")
	
	# Camera shaking in air to convey speed
	if not is_on_floor():
		if movement != Vector3.ZERO:
			shaking_anim.playback_speed = clamp(movement.length() / 30, 0, 3)
			shaking_anim.play("shake")
	elif shaking_anim.assigned_animation != "return":
			shaking_anim.stop()
			shaking_anim.play("return")
	
	floor_snap_length = snap.length()
	set_motion_velocity(movement)
	move_and_slide()


# Spawns some particles under the player
func spawn_jump_particles() -> void:
	$JumpParticles.restart()
	$JumpParticles.set_deferred("emitting", true)


# Play the jump sound with a random pitch
# @param min_pitch - Minimal pitch for the sound
# @param max-pitch - Maximum pitch for the sound
func play_jump_sound(min_pitch: float, max_pitch: float) -> void:
	$Sounds/Jump.pitch_scale = randf_range(min_pitch, max_pitch)
	$Sounds/Jump.stop()
	$Sounds/Jump.play()
