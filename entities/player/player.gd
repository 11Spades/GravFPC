extends CharacterBody3D


enum Items {
	DAGGER,
	RAPIER,
	BOW,
	BOTTLE,
	KUNAI,
	BOMB
}


const GROUND_DECELERATION_RATE = 64.0
const GROUND_ACCELERATION_RATE = 64.0
const AIR_ACCELERATION_RATE = 32.0
const MAX_WALK_SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.001
const SHORT_JUMP_FACTOR = 0.5


var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var gravity_vector = Vector3(0, -1, 0)
var camera
var current_target
var raycast_normal
var current_walk_velocity
var in_jump
var health: int = 3
var inventory: Dictionary = {Items.DAGGER: 1, Items.KUNAI: 1}
var currently_holding: Items = Items.DAGGER


func change_own_gravity_to(new_gravity_vector: Vector3) -> void:
	in_jump = false
	
	# Figure out which direction to rotate ourselves in
	var new_self_orientation = self.transform.basis.rotated(gravity_vector.cross(new_gravity_vector).normalized(), gravity_vector.angle_to(new_gravity_vector)) if gravity_vector.cross(new_gravity_vector) != Vector3.ZERO else self.transform.basis.rotated(gravity_vector.cross(Vector3(new_gravity_vector.y, -new_gravity_vector.z, new_gravity_vector.x)).normalized(), gravity_vector.angle_to(new_gravity_vector))
	
	# Rotate ourselves with a tween
	var reorienter_tween = get_tree().create_tween()
	reorienter_tween.tween_property(self, "transform:basis", new_self_orientation, 0.25)
	
	# Apply gravity changes
	gravity_vector = new_gravity_vector
	self.up_direction = -new_gravity_vector
	
	return


func do_secondary_fire() -> void:
	# Perform a raycast 1000 units and hopefully collide with something
	var mouse_position = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_position)
	var to = from + camera.project_ray_normal(mouse_position) * 1000
	var intersection = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self]))
	
	if !intersection:
		# Our ray didn't hit anything, but we want to manipulate our own gravity
		# Send us towards where our camera was pointing
		if Input.is_action_pressed("gravity_self"):
			change_own_gravity_to((to - from).normalized())
			
			return
			
		# Our ray didn't hit anything, but we already have an object ready for manipulation
		# Change that object's gravity to have it intersect with the point we were looking at
		if current_target:
			current_target.change_gravity((to - from).normalized() * gravity + Vector3(0, gravity, 0) * current_target.gravity_scale)
			current_target = null
			
			return
		
	# Our raycast had a hit and we want to manipulate our own gravity
	# Set our gravity to be the opposite of the vector normal to the face our raycast hit
	if Input.is_action_pressed("gravity_self"):
		change_own_gravity_to(-intersection["normal"])
		
		return
	
	if !intersection.has("collider"):
		return
	
	var collided_object = intersection["collider"]
	
	# Our raycast hit and we don't have an object queued for manipulation
	# Set this one to be manipulated
	if collided_object is GravityRigidBody3D and !current_target:
		current_target = collided_object
		return
	
	if !current_target:
		return
	
	# Our raycast hit and we have an object to change the gravity of
	# Set the object's gravity to be the opposite of normal to whatever face the raycast hit
	current_target.change_gravity((intersection.position - current_target.position + current_target.center_of_mass).normalized() * gravity + Vector3(0, gravity, 0) * current_target.gravity_scale)
	current_target = null
	
	return


func do_weapon_switch(direction: int) -> void:
	# Bootleg do-while to cycle through weapons
	currently_holding += direction
	
	if currently_holding < 0:
		currently_holding = Items.size() - 1
	elif Items.size() < currently_holding:
		currently_holding = 0
	
	while !inventory.has(currently_holding) || inventory[currently_holding] < 1:
		currently_holding += direction
		
		if currently_holding < 0:
			currently_holding = Items.size() - 1
		elif Items.size() < currently_holding:
			currently_holding = 0
	
	$PlayerCamera/DebugWeaponLabel.text = "Weapon: " + str(currently_holding)
	# TODO: Catch loops when empty-handed
	# TODO: Update model
	
	return


func shorten_hop() -> void:
	if 0 < (transform.basis.inverse() * velocity).y:
		velocity = transform.basis * Vector3((transform.basis.inverse() * velocity).x, (transform.basis.inverse() * velocity).y * SHORT_JUMP_FACTOR, (transform.basis.inverse() * velocity).z)
	
	return


func do_mouse_motion(event: InputEventMouseMotion):
	# Bounce camera X on backflip, make this a setting
	if abs(self.find_child("PlayerCamera").rotation.x) < PI/2:
		self.rotate(gravity_vector, event.relative.x * SENSITIVITY)
	else:
		self.rotate(gravity_vector, -event.relative.x * SENSITIVITY)
	
	self.find_child("PlayerCamera").rotate_x(-event.relative.y * SENSITIVITY)


func apply_vertical_forces(delta: float):
	if not self.is_on_floor():
		return gravity * gravity_vector * delta
	
	elif Input.is_action_pressed("jump"):
		in_jump = true
		return JUMP_VELOCITY * -gravity_vector
	
	return Vector3.ZERO


func apply_horizontal_forces(delta: float):
	# Get the input direction and convert it into a locally horizontal vector
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var relative_velocity = transform.basis.inverse() * velocity
	var relative_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	var desired_relative_velocity = transform.basis.inverse() * velocity
	
	# We have no direction
	if direction == Vector3.ZERO:
		if self.is_on_floor():
			return transform.basis * (relative_velocity.move_toward(Vector3.ZERO, GROUND_DECELERATION_RATE * delta) - relative_velocity)
		else:
			return Vector3.ZERO
	
	# We have a direction
	if self.is_on_floor(): # TODO: This can be simplified. I don't know how yet.
		if abs(relative_velocity.x) < MAX_WALK_SPEED:
			desired_relative_velocity.x = move_toward(relative_velocity.x, relative_direction.x * MAX_WALK_SPEED, GROUND_ACCELERATION_RATE * delta)
		else:
			desired_relative_velocity.x = move_toward(relative_velocity.x, relative_direction.x * MAX_WALK_SPEED, GROUND_DECELERATION_RATE * delta) if abs(relative_velocity.x) <= abs(relative_velocity.x + relative_direction.x) else move_toward(relative_velocity.x, relative_direction.x * MAX_WALK_SPEED, GROUND_ACCELERATION_RATE * delta)
	
		if abs(relative_velocity.z) < MAX_WALK_SPEED:
			desired_relative_velocity.z = move_toward(relative_velocity.z, relative_direction.z * MAX_WALK_SPEED, GROUND_ACCELERATION_RATE * delta)
		else:
			desired_relative_velocity.z = move_toward(relative_velocity.z, relative_direction.z * MAX_WALK_SPEED, GROUND_DECELERATION_RATE * delta) if abs(relative_velocity.z) <= abs(relative_velocity.z + relative_direction.z) else move_toward(relative_velocity.z, relative_direction.z * MAX_WALK_SPEED, GROUND_ACCELERATION_RATE * delta)
			
		return transform.basis * (desired_relative_velocity - relative_velocity)
		
	else:
		if abs(relative_velocity.x) < MAX_WALK_SPEED:
			desired_relative_velocity.x = move_toward(relative_velocity.x, relative_direction.x * MAX_WALK_SPEED, AIR_ACCELERATION_RATE * delta)
		else:
			desired_relative_velocity.x = relative_velocity.x if abs(relative_velocity.x) <= abs(relative_velocity.x + relative_direction.x) else move_toward(relative_velocity.x, relative_direction.x * MAX_WALK_SPEED, AIR_ACCELERATION_RATE * delta)
		
		if abs(relative_velocity.z) < MAX_WALK_SPEED:
			desired_relative_velocity.z = move_toward(relative_velocity.z, relative_direction.z * MAX_WALK_SPEED, AIR_ACCELERATION_RATE * delta)
		else:
			desired_relative_velocity.z = relative_velocity.z if abs(relative_velocity.z) <= abs(relative_velocity.z + relative_direction.z) else move_toward(relative_velocity.z, relative_direction.z * MAX_WALK_SPEED, AIR_ACCELERATION_RATE * delta)
			
		return transform.basis * (desired_relative_velocity - relative_velocity)


func lose_game() -> void:
	print("You lose.")
	return


func take_damage() -> void:
	if --health < 1:
		self.lose_game()
	return


func _ready():
	# Capture mouse inputs
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Switch the camera over to first person
	camera = $PlayerCamera


func _input(event):
	if event is InputEventMouseMotion:
		do_mouse_motion(event)
	
	if event.is_action_pressed("secondary_fire"):
		do_secondary_fire()
	
	if event.is_action_pressed("switch_weapon_forward"):
		do_weapon_switch(1)
	
	if event.is_action_pressed("switch_weapon_backward"):
		do_weapon_switch(-1)
	
	if event.is_action_released("jump") and in_jump:
		shorten_hop()


func _physics_process(delta):
	velocity += apply_vertical_forces(delta) + apply_horizontal_forces(delta)
	move_and_slide()
	
	# Push rigidbodies
	for col_idx in get_slide_collision_count():
		var col := get_slide_collision(col_idx)
		if col.get_collider() is RigidBody3D:
			col.get_collider().apply_central_impulse(-col.get_normal() * 0.3)
			col.get_collider().apply_impulse(-col.get_normal() * 0.01, col.get_position())
