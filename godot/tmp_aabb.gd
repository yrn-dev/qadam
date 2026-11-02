extends SceneTree
func _initialize():
	for id in ["counter","shelf"]:
		var res=load("res://assets/cartoon/prepared/%s.res"%id)
		print(id, " -> ", res)
		if res is PackedScene:
			var n=res.instantiate()
			var box=AABB()
			var first=true
			for m in n.find_children("*","MeshInstance3D",true,false):
				var b=AABB((n.global_transform.affine_inverse()*m.global_transform)*m.get_aabb())
				box=b if first else box.merge(b)
				first=false
			print(id, " aabb=", box)
		elif res is Mesh:
			print(id, " mesh aabb=", res.get_aabb())
	quit()
