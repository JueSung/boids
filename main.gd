extends Node2D

# var bird1_scene = preload("res://bird_1.tscn")

# var boids = []

# func _ready():
# 	for i in range(150):
# 		var inst = bird1_scene.instantiate()
# 		add_child(inst)
# 		boids.append(inst)
	
# 	var ins = preload("res://controller.tscn").instantiate()
# 	add_child(ins)
	


# func _physics_process(delta):
# 	for boid in boids:
# 		boid.do_thing(delta)



const BOID_COUNT := 1024 * 5
const BOID_SIZE := 16

var rd : RenderingDevice
var shader_clean
var shader_count
var shader_prefix
var shader_scatter
var shader_boids

var pipeline_clean
var pipeline_count
var pipeline_prefix
var pipeline_scatter
var pipeline_boids

var boid_buffer
var boid_buffer2
var ping_pong = false
var params_buffer

var uniform_set
var uniform_set2

var screen_size


func _ready() -> void:
	Engine.time_scale = 1

	var mm = MultiMesh.new()
	var qmesh = QuadMesh.new()
	qmesh.size = Vector2(8, 8)
	mm.mesh = qmesh
	mm.transform_format = MultiMesh.TRANSFORM_2D
	# mm.instance_count = BOID_COUNT
	
	$MultiMeshInstance2D.multimesh = mm

	screen_size = get_viewport_rect().size
	$MultiMeshInstance2D.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	$MultiMeshInstance2D.multimesh.mesh = qmesh
	$MultiMeshInstance2D.multimesh.instance_count = BOID_COUNT


	rd = RenderingServer.get_rendering_device()

	# load shader
	shader_clean = rd.shader_create_from_spirv(load("res://clean.glsl").get_spirv())
	pipeline_clean = rd.compute_pipeline_create(shader_clean)
	shader_count = rd.shader_create_from_spirv(load("res://count.glsl").get_spirv())
	pipeline_count = rd.compute_pipeline_create(shader_clean)
	shader_prefix = rd.shader_create_from_spirv(load("res://prefix.glsl").get_spirv())
	pipeline_prefix = rd.compute_pipeline_create(shader_clean)
	shader_scatter = rd.shader_create_from_spirv(load("res://scatter.glsl").get_spirv())
	pipeline_scatter = rd.compute_pipeline_create(shader_clean)
	shader_boids = rd.shader_create_from_spirv(load("res://boid.glsl").get_spirv())
	pipeline_boids = rd.compute_pipeline_create(shader_clean)
	

	# create boid data
	var boid_bytes = PackedByteArray()
	boid_bytes.resize(BOID_COUNT * BOID_SIZE)
	for i in BOID_COUNT:
		var offset = i * BOID_SIZE;
		var pos = Vector2(randf() * 1920, randf() * 1080)
		var vel = 500 * Vector2(randf()*2-1, randf()*2-1).normalized()

		boid_bytes.encode_float(offset + 0, pos.x)
		boid_bytes.encode_float(offset + 4, pos.y)
		boid_bytes.encode_float(offset + 8, vel.x)
		boid_bytes.encode_float(offset + 12, vel.y)

	boid_buffer = rd.storage_buffer_create(boid_bytes.size(), boid_bytes)
	boid_buffer2 = rd.storage_buffer_create(boid_bytes.size(), boid_bytes)
	
	# param buffer
	var param_bytes = PackedByteArray()
	param_bytes.resize(16) # std140 requires 16 bytes minimum
	param_bytes.encode_float(0, 0.0) # delta (updated each frame)
	param_bytes.encode_u32(4, BOID_COUNT)
	params_buffer = rd.uniform_buffer_create(param_bytes.size(), param_bytes)

	# create uniforms
	var boid_uniform = RDUniform.new()
	boid_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	boid_uniform.binding = 0
	boid_uniform.add_id(boid_buffer)

	var params_uniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params_uniform.binding = 1
	params_uniform.add_id(params_buffer)

	# create uniform set
	uniform_set = make_uniform_set(boid_buffer, boid_buffer2)
	uniform_set2 = make_uniform_set(boid_buffer2, boid_buffer)

func _physics_process(delta: float) -> void:
	var active_set = uniform_set if not ping_pong else uniform_set2
	var write_buf = boid_buffer2 if not ping_pong else boid_buffer

  # update params
	var param_bytes = PackedByteArray()
	param_bytes.resize(16)
	param_bytes.encode_float(0, delta)
	param_bytes.encode_u32(4, BOID_COUNT)
	rd.buffer_update(params_buffer, 0, param_bytes.size(), param_bytes)

	# dispatch
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_clean)
	rd.compute_list_bind_uniform_set(compute_list, active_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(BOID_COUNT / 256.0)), 1, 1)
	rd.compute_list_end()

	# read from write_buf BEFORE flipping
	var bytes = rd.buffer_get_data(write_buf)
	
	ping_pong = !ping_pong  # flip AFTER readback

	for i in BOID_COUNT:
			var offset = i * BOID_SIZE
			var pos = Vector2(
					bytes.decode_float(offset + 0),
					bytes.decode_float(offset + 4)
			)
			var vel = Vector2(
					bytes.decode_float(offset + 8),
					bytes.decode_float(offset + 12)
			)
			var t = Transform2D(vel.angle(), pos)
			$MultiMeshInstance2D.multimesh.set_instance_transform_2d(i, t)


func make_uniform_set(read_buf, write_buf):
	var read_uniform = RDUniform.new()
	read_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	read_uniform.binding = 0
	read_uniform.add_id(read_buf)
	var write_uniform = RDUniform.new()
	write_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	write_uniform.binding = 2  # new binding for write buffer
	write_uniform.add_id(write_buf)
	var params_uniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params_uniform.binding = 1
	params_uniform.add_id(params_buffer)
	return rd.uniform_set_create([read_uniform, params_uniform, write_uniform], shader_boids, 0)
