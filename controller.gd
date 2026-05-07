extends Area2D

var intersecting_bodies = []

func _ready():
	$CollisionShape2D.disabled = true
	connect("area_entered", body_entered)
	connect("area_exited", body_exited)
	
func _physics_process(delta):
	global_position = get_global_mouse_position()
	if Input.is_action_pressed("left_click"):
		$CollisionShape2D.visible = true
		$CollisionShape2D.disabled = false
	else:
		$CollisionShape2D.visible = false
		$CollisionShape2D.disabled = true
	
	for i in range(len(intersecting_bodies)):
		#intersecting_bodies[i].global_position += 7	 * (intersecting_bodies[i]["position"]-global_position) * delta
		var dir = (intersecting_bodies[i].global_position - global_position)
		intersecting_bodies[i].rotation = atan2(dir.y, dir.x)


func body_entered(body):
	intersecting_bodies.append(body)

func body_exited(body):
	intersecting_bodies.erase(body)
