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
## Being a cone rather than a box is also why it carries a `RoofContamination`
## and not a `ContaminableObject` or a `BodyContamination`. The first unwraps a
## box -- six flat faces with a grid each. The second wraps about an axis, which
## is right for a capsule and wrong here: every angle meets at the apex, so a
## splat came out as a wedge tapering to nothing at the point and a roof with a
## few shots on it read as a sunburst. The third lays the cone out as its own
## flat net, which a cone has exactly. One grid instead of six, and the same
## grid, deterministic paint and two-int network splat as everything else.

var contamination: RoofContamination
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

	contamination = RoofContamination.new()
	contamination.name = "RoofContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	add_child(contamination)
	contamination.configure(self, mesh_instance, base_radius, roof_height, color)


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
