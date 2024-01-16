extends CharacterBody3D

const ground_speed = 8.0
const wallrun_speed = 12.0
const wall_vert_speed = -2.0
const air_speed = 24.0

const walk_traction = 40.0
const walk_friction = 30.0
const slide_traction = 3.0
const slide_friction = 3.0
const wall_traction = 8.0
const wall_friction = 8.0
const air_traction = 12.0
const air_friction = 8.0

const slide_init_speed = 18.0
const dash_init_speed = 24.0
const jump_init_speed = 6.0
const walljump_init_speed = 12.0

const walljump_angle = PI/6
const wallclimb_angle = PI/6
const wallclimb_conversion = 0.8
const wallrun_min_speed = 9.0
const wallrun_momentum_conversion = 0.6
const wallrun_max_momentum = 12.0

const air_gravity = 16.0
const wall_gravity = 12.0

const slide_jump_boost = 3.0

const dash_cooldown = 0.5

const grapple_exponent = 1.0
const grapple_strength = 300 / 100.0

var max_dashes = 99
var num_dashes = max_dashes

var is_grappling = false
var is_sliding = false
var stored_momentum = Vector3.ZERO
var is_wallrunning = false
var is_slamming = false

@onready var head_pos_target = $StandingHeadMarker.position
var slide_anim_speed = 12

const mouse_sens = 3.0 / 1000

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sens)
		$Head.rotate_x(-event.relative.y * mouse_sens)
		$Head.rotation.x = clamp($Head.rotation.x, -PI/2 + 0.01, PI/2 - 0.01)

func _physics_process(delta):
	var local_velocity = transform.basis.inverse() * velocity
	var input_dir = Input.get_vector("Left", "Right", "Forward", "Backward")
	
	var move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()
	var target_move_speed
	var traction
	var friction
	
	# Shoot grapple
	if can_grapple() && Input.is_action_just_pressed("Grapple"):
		is_grappling = true
		%GrapplePoint.update_position = false
	if Input.is_action_just_released("Grapple"):
		is_grappling = false
		%GrapplePoint.update_position = true
	
	# Start dash
	if can_dash() && Input.is_action_just_pressed("Dash"):
		if num_dashes == max_dashes:
			$DashCooldown.start(dash_cooldown)
		num_dashes -= 1
		var dash_dir = move_dir if move_dir else Vector3.FORWARD
		local_velocity.x = dash_dir.x * dash_init_speed
		local_velocity.z = dash_dir.z * dash_init_speed
	
	# Start slide
	if Input.is_action_pressed("Slide"):
		if can_slide():
			is_sliding = true
			update_pose()
		elif can_slam():
			is_slamming = true
	# End slide
	if can_stand() && !Input.is_action_pressed("Slide"):
		is_sliding = false
		update_pose()
	
	var wall_normal = transform.basis.inverse() * get_wall_normal()

	# Start wallrun
	if is_on_wall() && !is_wallrunning && stored_momentum.length() > wallrun_min_speed:
		is_wallrunning = true
		is_sliding = false
		update_pose()
		
		var lost_momentum = stored_momentum.project(wall_normal)
		var momentum_transfer = min(wallrun_momentum_conversion * lost_momentum.length(), wallrun_max_momentum)
		var momentum_dir = (stored_momentum - lost_momentum).normalized()
		if stored_momentum.angle_to(-wall_normal) < wallclimb_angle:
			momentum_dir = Vector3.UP * wallclimb_conversion
		local_velocity += momentum_dir * momentum_transfer
	# Verify wallrun
	else: is_wallrunning = is_on_wall_only()
	
	# Ground
	if is_on_floor():
		# Slide
		if is_sliding:
			traction = slide_traction
			friction = slide_friction
		# Walk
		else:
			traction = walk_traction
			friction = walk_friction
		target_move_speed = ground_speed
	# Wall
	elif is_on_wall_only():
		target_move_speed = wallrun_speed
		traction = wall_traction
		friction = wall_friction
		local_velocity.y -= wall_gravity * delta
		local_velocity.y = max(wall_vert_speed, local_velocity.y)
	# Air
	else:
		target_move_speed = air_speed
		traction = air_traction
		friction = air_friction
		local_velocity.y -= air_gravity * delta
	
	# Start jump
	if can_jump() && Input.is_action_just_pressed("Jump"):
		# Walljump
		if is_wallrunning:
			is_wallrunning = false
			var walljump_dir = (wall_normal + tan(walljump_angle) * Vector3.UP).normalized()
			local_velocity += walljump_dir * walljump_init_speed
		
		# Slidejump
		elif is_sliding:
			is_sliding = false
			local_velocity.x += move_dir.x * slide_jump_boost
			local_velocity.z += move_dir.z * slide_jump_boost
			local_velocity.y = jump_init_speed
			update_pose()
		
		# Jump
		else:
			local_velocity.y = jump_init_speed
	
	var accel = traction if local_velocity.length() < target_move_speed else friction
	local_velocity.x = move_toward(local_velocity.x, move_dir.x * target_move_speed, accel * delta)
	local_velocity.z = move_toward(local_velocity.z, move_dir.z * target_move_speed, accel * delta)
	
	if is_grappling:
		var rel_grapple_pos = transform.basis.inverse() * ($GrappleHook.position - position)
		var grapple_dir = rel_grapple_pos.normalized()
		var grapple_len = rel_grapple_pos.length()
		local_velocity += grapple_dir * (grapple_len ** grapple_exponent) * grapple_strength * delta
	elif is_wallrunning:
		var converted_momentum = local_velocity.project(wall_normal)
		local_velocity -= converted_momentum
	stored_momentum = local_velocity
	
	$Head.position = $Head.position.move_toward(head_pos_target, slide_anim_speed * delta)
	
	velocity = transform.basis * local_velocity
	up_direction = (transform.basis * Vector3.UP).normalized()
	move_and_slide()

func can_grapple():
	return true

func can_dash():
	return num_dashes > 0 && !is_wallrunning

func can_slam():
	return !is_on_floor() && !is_wallrunning

func can_slide():
	return is_on_floor() && !is_sliding

func can_stand():
	return is_sliding

func can_jump():
	return is_on_floor() || is_on_wall()

func update_pose():
	# Sliding
	if is_sliding:
		$SlidingHitbox.disabled = false
		$StandingHitbox.disabled = true
		head_pos_target = $SlidingHeadMarker.position
	# Standing
	else:
		$SlidingHitbox.disabled = true
		$StandingHitbox.disabled = false
		head_pos_target = $StandingHeadMarker.position

func _on_dash_timer_timeout():
	num_dashes += 1
	if num_dashes != max_dashes:
		$DashCooldown.start(dash_cooldown)
