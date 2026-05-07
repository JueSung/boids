extends Area2D


var nearby_birds = {}

const MAX_ROT_VEL : float = 2 * PI / 2

var screen_size

var linear_velocity : Vector2 = Vector2.ZERO

var dum_cooldown = 1

func _ready():
	screen_size = get_viewport_rect().size
	global_position = Vector2(randf() * 1920, randf() * 1080)
	rotation = randf() * 2 * PI
	linear_velocity = 500 * Vector2(cos(rotation), sin(rotation)).normalized()
	$Area2D.connect("area_entered", body_nearby)
	$Area2D.connect("area_exited", body_not_nearby)
	


func do_thing(delta):
	var avg_pos : Vector2 = Vector2.ZERO
	var avg_rot : float = 0.0
	var avg_look : Vector2 = Vector2.ZERO
	var separation = Vector2.ZERO
	for bird in nearby_birds:
		avg_pos += bird.global_position
		avg_look += Vector2(cos(bird.rotation), sin(bird.rotation))
		var temp = (global_position-bird.global_position)
		if temp.length() != 0:
			separation += temp / (temp.length() * temp.length())
	if nearby_birds.size() > 0:
		avg_pos /= float(nearby_birds.size())
		avg_look /= float(nearby_birds.size())
	#separation /= float(len(nearby_birds))
	avg_rot = atan2(avg_look.y, avg_look.x)
	while avg_rot > 2 * PI:
		avg_rot -= 2 * PI
	
	#var normal_dir = Vector2(-sin(rotation), cos(rotation))
	#var proj = (normal_dir.dot(avg_pos) / (normal_dir.dot(normal_dir)) * normal_dir).normalized()
	#if proj.dot(avg_pos-global_position) < 0:
	#	proj *= -1
	var cohesion = (avg_pos - global_position).normalized()
	
	
	var align = Vector2(cos(avg_rot), sin(avg_rot)).normalized()

	var target_position = get_global_mouse_position()
	var target : Vector2 = (target_position - global_position).normalized()
	
	var final = align * .6 + cohesion * .6 + separation * 6# + 3 * (target)/(sqrt((target_position-global_position).length()/30))
	
	var target_rot : float = atan2(final.y, final.x)
	# normalize about -pi to pi
	var angle_diff = normalize_rotation(target_rot - rotation)
	if angle_diff > 0:
		rotation += MAX_ROT_VEL * delta
	else:
		rotation -= MAX_ROT_VEL * delta
	
	
	linear_velocity = 500 * Vector2(cos(rotation), sin(rotation))
	
	global_position += linear_velocity * delta
	
	position.x = wrapf(position.x, 0, screen_size.x)
	position.y = wrapf(position.y, 0, screen_size.y)

	# dum_cooldown -= delta
	# if (global_position - target_position).length() < 50 && dum_cooldown < 0:
	# 	dum_cooldown = 1
	# 	if ($Sprite2D.visible):
	# 		pass
	# 		# $Sprite2D.visible = false
	# 	else:
	# 		$Sprite2D.visible = true


func normalize_rotation(rot):
	while (rot < -PI):
		rot += 2*PI
	while rot > PI:
		rot -= 2*PI
	return rot


func body_nearby(area) -> void:
	nearby_birds[area] = 1


func body_not_nearby(area) -> void:
	nearby_birds.erase(area)
