extends RigidBody3D


class_name GravityRigidBody3D


var gravity_indicator
var default_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var indicator_material = ORMMaterial3D.new()


func _ready():
	gravity_indicator = MeshInstance3D.new()
	gravity_indicator.name = "GravityIndicator"
	gravity_indicator.mesh = ImmediateMesh.new()
	self.add_child(gravity_indicator)


func _physics_process(delta):
	gravity_indicator.global_rotation = Vector3.ZERO


func change_gravity(gravity_vector: Vector3):
	set_constant_force(gravity_vector)

	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator_material.albedo_color = Color.BLACK
	indicator_material.set_flag(BaseMaterial3D.FLAG_DISABLE_DEPTH_TEST, true)

	var gravity_indicator_mesh = ImmediateMesh.new()
	gravity_indicator_mesh.surface_begin(Mesh.PRIMITIVE_LINES, indicator_material)
	gravity_indicator_mesh.surface_add_vertex(Vector3(0, 0, 0))
	gravity_indicator_mesh.surface_add_vertex((self.constant_force - Vector3(0, default_gravity, 0) * self.gravity_scale).normalized() * 2)
	gravity_indicator_mesh.surface_end()

	gravity_indicator.mesh = gravity_indicator_mesh
