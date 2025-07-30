extends Node

func _ready() -> void:
	var verts: PackedVector3Array = [
		Vector3(-64, -64, 0),
		Vector3(-64, 64, 0),
		Vector3(64, -64, 0),
		Vector3(64, 64, 0),
		Vector3(-64, -64, 128),
		Vector3(-64, 64, 128),
		Vector3(64, -64, 128),
		Vector3(64, 64, 128),
		Vector3(0, 96, 128),
		Vector3(0, 128, 64),
		Vector3(-96, 0, 192)
	]
	print(GenerateConvexHull(verts))
	

func GenerateConvexHull(shape_vertices: PackedVector3Array) -> Array[PackedVector3Array]:
	# gift wrapping method
	# TODO: replace with quickhull
	
	assert(shape_vertices.size() >= 4, "ERROR: at least 4 points are required to form a convex hull!")
	var vertices := shape_vertices.duplicate()
	
	# find the 3 lowest (z) verts
	var lowest_verts: PackedVector3Array
	for i in range(3):
		var lowest := INF # start at +infinity
		var current_best_vert: Vector3
		for vert in vertices:
			if vert in lowest_verts: continue # skip already found verts
			if vert.z < lowest: # TODO: fix when multiple points have the same z
				lowest = vert.z
				current_best_vert = vert
		lowest_verts.append(current_best_vert)
	
	var planes: Array[PackedVector3Array]
	
	var vec_ba := lowest_verts[0] - lowest_verts[1]
	var vec_bc := lowest_verts[2] - lowest_verts[1]
	
	assert(vec_ba.cross(vec_bc).z != 0, "ERROR: lowest polygon is vertical") # FIXME
	if vec_ba.cross(vec_bc).z > 0:
		# normal according to source points into the shape
		# swap the first and last vert to have the face point the opposite way
		var swap = lowest_verts[0]
		lowest_verts[0] = lowest_verts[2]
		lowest_verts[2] = swap
	
	planes.append(lowest_verts)
	
	var completed_edges: Array[Dictionary]
	
	while not vertices.size() - completed_edges.size() + planes.size() == 2: # until the hull is complete
		# euler characteristic == 2 for all closed convex polyhedra
		for plane in planes:
			for i in range(plane.size()):
				# check if edge is already done
				if {plane[i]: null, plane[i - 1]: null} in completed_edges:
					continue
				
				# NOTE: we do i - 1 cause idk if doing an index past the end loops around, but this def does
				var edge := plane[i] - plane[i - 1] # this order ensures the next face is the right way around
				var normal := (plane[0] - plane[1]).cross(plane[2] - plane[1])
				var next_plane: PackedVector3Array = [plane[i], plane[i - 1]]
				
				var decrease_rotation_amount := false
				var rotation_amount := 30.0
				var rotated := 0.0
				while true: # until we've found the next plane
					if decrease_rotation_amount:
						rotation_amount /= 2
					assert(rotated < 180, "ERROR: no vertex found!")
					var points_behind_plane: PackedVector3Array
					for vert in vertices:
						# equation for a plane: a(x - x0) + b(y - y0) + c(z - z0) = 0 
						# where the normal is (a, b, c)
						# sub point in for (x, y, z) to check side, pos is normal side
						if vert in next_plane: continue
						if normal.x * (vert.x - next_plane[0].x) + \
						normal.y * (vert.y - next_plane[0].y) + \
						normal.z * (vert.z - next_plane[0].z) > 0:
							points_behind_plane.append(vert)
					if points_behind_plane.size() == 0:
						# change angle of plane normal and go again
						normal = _RotatePerpendicularVector(normal, edge, -rotation_amount)
						rotated += rotation_amount
						continue
					else: # we found points behind the plane
						# test if all found points lie in a plane
						var normal_test := (next_plane[0] - next_plane[1]).cross(
							points_behind_plane[0] - next_plane[1]
						)
						var all_in_plane := true
						for vert_test in points_behind_plane:
							if normal_test.x * (vert_test.x - next_plane[0].x) + \
							normal_test.y * (vert_test.y - next_plane[0].y) + \
							normal_test.z * (vert_test.z - next_plane[0].z) != 0:
								all_in_plane = false
								break
						if not all_in_plane:
							# rotate normal backwards and go again
							if not decrease_rotation_amount:
								decrease_rotation_amount = true
								rotation_amount /= 2
							normal = _RotatePerpendicularVector(normal, edge, rotation_amount)
							rotated -= rotation_amount
							continue
						else:
							# if we make it here all the points are in a plane
							next_plane.append_array(points_behind_plane)
							next_plane = _MakeVerticesClockwise(next_plane)
							planes.append(next_plane)
							
							# update edges
							var edges: Array[Dictionary]
							for plane_test in planes:
								for j in range(plane_test.size()):
									var edge_test := {plane_test[j]: null, plane_test[j - 1]: null}
									if edge_test in completed_edges: continue
									elif edge_test in edges:
										completed_edges.append(edge_test)
									else:
										edges.append(edge_test)
							
							break
	return planes

func _RotatePerpendicularVector(vector: Vector3, axis: Vector3, angle_deg: float) -> Vector3:
	# https://math.stackexchange.com/questions/511370/how-to-rotate-one-vector-about-another
	# assumes vector is perpendicular to axis
	# right hand rule: thumb is axis, curl of fingers is dir of angle
	var angle_rad := deg_to_rad(angle_deg)
	var w := axis.cross(vector)
	var x1 := cos(angle_rad) / vector.length()
	var x2 := sin(angle_rad) / w.length()
	var rotated_vector := vector.length() * (x1 * vector + x2 * w)
	return rotated_vector

func _MakeVerticesClockwise(plane: PackedVector3Array) -> PackedVector3Array:
	# https://stackoverflow.com/questions/14370636/sorting-a-list-of-3d-coplanar-points-to-be-clockwise-or-counterclockwise
	var plane_unpacked := Array(plane)
	var center := Vector3.ZERO
	for point in plane:
		center += point
	center /= plane.size()
	var normal := (plane[0] - plane[1]).cross(plane[2] - plane[1])
	plane_unpacked.sort_custom(func(a, b): return normal.dot((a-center).cross(b-center)) < 0)
	return PackedVector3Array(plane_unpacked)
