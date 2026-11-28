extends RefCounted

const DROPLET_MESH := preload("res://assets/cartoon/water_droplet.tres")


## Visual-only spray. Omitting GPU collision keeps the same emitter usable in
## Compatibility. The hose and shower call sites still own contact and washing.
static func make(amount: int, lifetime: float, radius: float, speed: Vector2,
		scale_range: Vector2) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.DOWN
	motion.initial_velocity_min = speed.x
	motion.initial_velocity_max = speed.y
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = radius
	motion.particle_flag_align_y = true
	motion.scale_min = scale_range.x
	motion.scale_max = scale_range.y

	var spray := GPUParticles3D.new()
	spray.emitting = false
	spray.amount = amount
	spray.lifetime = lifetime
	spray.fixed_fps = 60
	spray.local_coords = false
	spray.visibility_aabb = AABB(Vector3(-1.0, -5.0, -1.0), Vector3(2.0, 5.5, 2.0))
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.draw_pass_1 = DROPLET_MESH
	spray.process_material = motion
	return spray
