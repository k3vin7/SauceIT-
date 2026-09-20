class_name StallRoof
extends StaticBody3D

## The pointed roof of a market stall: the thing that actually stops a shot
## fired over one.
##
## It used to be a flat slab at eaves height with a decorative pyramid sitting
## on top of it, which is not what a gazebo is -- sauce arriving over the stall
## stopped dead on an invisible ceiling instead of running down the slope you
## can see. The collider is the pyramid now, taken from the very mesh that is
## drawn, so the silhouette that blocks and the silhouette on screen cannot
## disagree.
##
## Being a cone rather than a box is also why it is a `BodyContamination` and
## not a `ContaminableObject`. That one unwraps a box, six flat faces with a
## grid each; this one unwraps about an axis, which is exactly right for a
## surface of revolution -- and a square pyramid is one, sampled four times
## round. One grid instead of six, and it is the same grid, shader and two-int
## network splat as everything else.

var contamination: BodyContamination
var radius := 1.0
var height := 1.0


func _ready() -> void:
	add_to_group("mayo_roof")
	# What the strand looks for.
	add_to_group("mayo_contaminable")


func build(base_radius: float, roof_height: float, cell_size: float,
		brush_radius: float, color: Color) -> void:
	radius = base_radius
	height = roof_height

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = base_radius
	cone.height = roof_height
	# Four sides: a pyramid, not a cone. The unwrap does not care -- it maps by
	# angle, and a square pyramid is a surface of revolution sampled four times.
	cone.radial_segments = 4
	cone.rings = 1

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoofMesh"
	mesh_instance.mesh = cone
	add_child(mesh_instance)

	# The collider is built from the drawn mesh's own triangles rather than from
	# five points worked out by hand: `CylinderMesh` decides for itself which
	# angle its first vertex sits at, and a hull guessed at from the radius
	# would be turned a quarter-face against the thing on screen.
	var hull := ConvexPolygonShape3D.new()
	hull.points = cone.get_faces()
	var collision := CollisionShape3D.new()
	collision.name = "RoofCollision"
	collision.shape = hull
	add_child(collision)

	contamination = BodyContamination.new()
	contamination.name = "BodyContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	add_child(contamination)
	# Two thirds of the base radius: the area-weighted mean radius of a cone.
	# The unwrap turns grid metres into surface metres by one radius, and a cone
	# has a different one at every height, so this is the one that makes a splat
	# the right size over most of the roof. Right at the apex it still smears,
	# because every angle meets there -- the same limitation the enemy's limbs
	# have, and the same fix would be needed for both.
	contamination.configure(self, mesh_instance, base_radius * (2.0 / 3.0),
		roof_height, color)


func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal)


func paint_mayo_cell(cell: Vector2i) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell)


func cells_md5() -> String:
	return contamination.cells_md5() if contamination != null else ""


## Height of the apex above the roof's own centre, for the checks.
func apex_height() -> float:
	return height * 0.5
