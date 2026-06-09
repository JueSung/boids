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



var boid_count : int = 1024 * 50
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
var count_buffer
var index_offsets_buffer
var offsets_buffer
var transform_buffer

# num of cells wide and tall
const WIDTH = 32
const HEIGHT = 32

const VIEWPORT_WIDTH = 1920 * 2
const VIEWPORT_HEIGHT = 1080 * 2

const WORK_GROUP_SIZE = 1024.0

var clean_uniform_set
var count_uniform_set
var count_uniform_set2
var prefix_uniform_set
var scatter_uniform_set
var scatter_uniform_set2
var boid_uniform_set
var boid_uniform_set2


var screen_size


func _ready() -> void:
	Engine.time_scale = 1

	var mm = MultiMesh.new()
	var qmesh = QuadMesh.new()
	qmesh.size = Vector2(8, 8)
	mm.mesh = qmesh
	mm.transform_format = MultiMesh.TRANSFORM_2D
	# mm.instance_count = boid_count
	
	$MultiMeshInstance2D.multimesh = mm

	screen_size = get_viewport_rect().size
	$MultiMeshInstance2D.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	$MultiMeshInstance2D.multimesh.mesh = qmesh
	$MultiMeshInstance2D.multimesh.instance_count = boid_count


	rd = RenderingServer.get_rendering_device()
	
	# load shader
	shader_clean = rd.shader_create_from_spirv(load("res://clean.glsl").get_spirv())
	pipeline_clean = rd.compute_pipeline_create(shader_clean)
	shader_count = rd.shader_create_from_spirv(load("res://count.glsl").get_spirv())
	pipeline_count = rd.compute_pipeline_create(shader_count)
	shader_prefix = rd.shader_create_from_spirv(load("res://prefix.glsl").get_spirv())
	pipeline_prefix = rd.compute_pipeline_create(shader_prefix)
	shader_scatter = rd.shader_create_from_spirv(load("res://scatter.glsl").get_spirv())
	pipeline_scatter = rd.compute_pipeline_create(shader_scatter)
	shader_boids = rd.shader_create_from_spirv(load("res://boid.glsl").get_spirv())
	pipeline_boids = rd.compute_pipeline_create(shader_boids)
	

	# create boid data
	var boid_bytes = PackedByteArray()
	boid_bytes.resize(boid_count * BOID_SIZE)
	for i in boid_count:
		var offset = i * BOID_SIZE;
		var pos = Vector2(randf() * VIEWPORT_WIDTH, randf() * VIEWPORT_HEIGHT)
		var vel = 100 * Vector2(randf()*2-1, randf()*2-1).normalized()

		boid_bytes.encode_float(offset + 0, pos.x)
		boid_bytes.encode_float(offset + 4, pos.y)
		boid_bytes.encode_float(offset + 8, vel.x)
		boid_bytes.encode_float(offset + 12, vel.y)

	boid_buffer = rd.storage_buffer_create(boid_bytes.size(), boid_bytes)
	boid_buffer2 = rd.storage_buffer_create(boid_bytes.size(), boid_bytes)
	
	# param buffer
	var param_bytes = PackedByteArray()
	param_bytes.resize(68) # std140 requires 16 bytes minimum
	param_bytes.encode_float(0, 0.0) # delta (updated each frame)
	param_bytes.encode_u32(4, boid_count)
	param_bytes.encode_float(8, 1.2)
	param_bytes.encode_float(12, 0.5)
	param_bytes.encode_float(16, 100)
	param_bytes.encode_float(20, 8)
	param_bytes.encode_float(24, 80)
	param_bytes.encode_float(28, 40)
	param_bytes.encode_float(32, 300)
	params_buffer = rd.uniform_buffer_create(param_bytes.size(), param_bytes)

	# clean buffer and index_offsets_buffer
	var count_bytes = PackedByteArray()
	var index_offsets_bytes = PackedByteArray()
	count_bytes.resize(WIDTH * HEIGHT * 4)
	index_offsets_bytes.resize(WIDTH * HEIGHT * 4)
	for i in range(WIDTH * HEIGHT):
		count_bytes.encode_u32(i * 4, 0)
		index_offsets_bytes.encode_u32(i * 4, 0)
	count_buffer = rd.storage_buffer_create(count_bytes.size(), count_bytes)
	index_offsets_buffer = rd.storage_buffer_create(index_offsets_bytes.size(), index_offsets_bytes)
	
	# offsets_buffer
	var offsets_bytes = PackedByteArray()
	offsets_bytes.resize(boid_count * 4)
	
	for i in range(boid_count):
		offsets_bytes.encode_u32(i * 4, 0)
	offsets_buffer = rd.storage_buffer_create(offsets_bytes.size(), offsets_bytes)
	
	# transform set
	var transform_bytes = PackedByteArray()
	transform_bytes.resize(boid_count * 8 * 4)
	
	for i in range(boid_count * 8):
		transform_bytes.encode_float(i * 4, 0)

	transform_buffer = rd.storage_buffer_create(transform_bytes.size(), transform_bytes)
	
	# uniform sets
	clean_uniform_set = make_clean_uniform_set()
	count_uniform_set = make_count_uniform_set(boid_buffer)
	count_uniform_set2 = make_count_uniform_set(boid_buffer2)
	prefix_uniform_set = make_prefix_uniform_set()
	scatter_uniform_set = make_scatter_uniform(boid_buffer)
	scatter_uniform_set2 = make_scatter_uniform(boid_buffer2)
	
	# create boid uniform set
	boid_uniform_set = make_uniform_set(boid_buffer, boid_buffer2)
	boid_uniform_set2 = make_uniform_set(boid_buffer2, boid_buffer)
	

func _physics_process(delta: float) -> void:
	var active_boid_set = boid_uniform_set if not ping_pong else boid_uniform_set2
	var write_buf = boid_buffer2 if not ping_pong else boid_buffer
	var active_count_set = count_uniform_set if not ping_pong else count_uniform_set2
	var active_scatter_set = scatter_uniform_set if not ping_pong else scatter_uniform_set2

  # update params
	var param_bytes = PackedByteArray()
	param_bytes.resize(68)
	param_bytes.encode_float(0, delta)
	# print(int($HUD/boid_count.value) == 1024 * 20)
	# print(int($HUD/boid_count.value))
	# print(1024 * 20)
	#boid_count = int($HUD/boid_count.value)
	param_bytes.encode_u32(4, int($HUD/boid_count.value))
	param_bytes.encode_float(8, float($HUD/cohesion.value))
	param_bytes.encode_float(12, float($HUD/alignment.value))
	param_bytes.encode_float(16, float($HUD/separation.value))
	param_bytes.encode_float(20, float($HUD/turn_speed.value))
	param_bytes.encode_float(24, float($HUD/neighbor_radius.value))
	param_bytes.encode_float(28, float($HUD/separation_radius.value))
	param_bytes.encode_float(32, float($HUD/speed.value))
	rd.buffer_update(params_buffer, 0, param_bytes.size(), param_bytes)

	$HUD/boid_count/Label2.text = str($HUD/boid_count.value)
	$MultiMeshInstance2D.multimesh.visible_instance_count = int($HUD/boid_count.value)

	$HUD/cohesion/Label2.text = str($HUD/cohesion.value)
	$HUD/alignment/Label2.text = str($HUD/alignment.value)
	$HUD/separation/Label2.text = str($HUD/separation.value)
	$HUD/turn_speed/Label2.text = str($HUD/turn_speed.value)
	$HUD/neighbor_radius/Label2.text = str($HUD/neighbor_radius.value)
	$HUD/separation_radius/Label2.text = str($HUD/separation_radius.value)
	$HUD/speed/Label2.text = str($HUD/speed.value)

	# dispatch clean
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_clean)
	rd.compute_list_bind_uniform_set(compute_list, clean_uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(WIDTH * HEIGHT / WORK_GROUP_SIZE)), 1, 1)
	rd.compute_list_end()

	# dispatch count
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_count)
	rd.compute_list_bind_uniform_set(compute_list, active_count_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(boid_count / WORK_GROUP_SIZE)), 1, 1)
	rd.compute_list_end()
	# var bytess = rd.buffer_get_data(count_buffer)
	# var arr = []
	# for i in range(WIDTH * HEIGHT):
	# 		arr.append(int(bytess.decode_u32(i * 4)))
	# print("START")
	# print(arr)

	#dispatch prefix
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_prefix)
	rd.compute_list_bind_uniform_set(compute_list, prefix_uniform_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(WIDTH * HEIGHT / WORK_GROUP_SIZE)), 1, 1)
	rd.compute_list_end()
	# var bytess = rd.buffer_get_data(index_offsets_buffer)
	# var arr = []
	# for i in range(WIDTH * HEIGHT):
	# 		arr.append(int(bytess.decode_u32(i * 4)))
	# print(arr)

	# dispatchs scatter
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_scatter)
	rd.compute_list_bind_uniform_set(compute_list, active_scatter_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(boid_count / WORK_GROUP_SIZE)), 1, 1)
	rd.compute_list_end()

	# dispatch boids
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_boids)
	rd.compute_list_bind_uniform_set(compute_list, active_boid_set, 0)
	rd.compute_list_dispatch(compute_list, int(ceil(boid_count / WORK_GROUP_SIZE)), 1, 1)
	rd.compute_list_end()
	# bytess = rd.buffer_get_data(offsets_buffer)
	# arr = []
	# for i in range(boid_count):
	# 	arr.append(int(bytess.decode_u32(i*4)))
	# print(arr)

	# read from write_buf BEFORE flipping
	var bytes = rd.buffer_get_data(transform_buffer)
	# print(Vector2(bytes.decode_float(BOID_SIZE + 8), bytes.decode_float(BOID_SIZE + 12)))
	
	ping_pong = !ping_pong  # flip AFTER readback

	RenderingServer.multimesh_set_buffer($MultiMeshInstance2D.multimesh.get_rid(), bytes.to_float32_array())

	# for i in boid_count:
	# 		var offset = i * BOID_SIZE
	# 		var pos = Vector2(
	# 				bytes.decode_float(offset + 0),
	# 				bytes.decode_float(offset + 4)
	# 		)
	# 		var vel = Vector2(
	# 				bytes.decode_float(offset + 8),
	# 				bytes.decode_float(offset + 12)
	# 		)
	# 		var t = Transform2D(vel.angle(), pos)
	# 		$MultiMeshInstance2D.multimesh.set_instance_transform_2d(i, t)


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
	var ind_off_uniform = RDUniform.new()
	ind_off_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ind_off_uniform.binding = 3
	ind_off_uniform.add_id(index_offsets_buffer)
	var offsets_uniform = RDUniform.new()
	offsets_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	offsets_uniform.binding = 4
	offsets_uniform.add_id(offsets_buffer)
	var transform_uniform = RDUniform.new()
	transform_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	transform_uniform.binding = 5
	transform_uniform.add_id(transform_buffer)

	return rd.uniform_set_create([read_uniform, params_uniform, write_uniform, ind_off_uniform, offsets_uniform, transform_uniform], shader_boids, 0)

func make_clean_uniform_set():
	var c_uniform = RDUniform.new()
	c_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	c_uniform.binding = 0
	c_uniform.add_id(count_buffer)
	return rd.uniform_set_create([c_uniform], shader_clean, 0)

func make_count_uniform_set(read_buf):
	var read_uniform = RDUniform.new()
	read_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	read_uniform.binding = 0
	read_uniform.add_id(read_buf)
	
	var c_uniform = RDUniform.new()
	c_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	c_uniform.binding = 1
	c_uniform.add_id(count_buffer)
	return rd.uniform_set_create([read_uniform, c_uniform], shader_count, 0)

func make_prefix_uniform_set():
	var c_uniform = RDUniform.new()
	c_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	c_uniform.binding = 0
	c_uniform.add_id(count_buffer)

	var ind_off_uniform = RDUniform.new()
	ind_off_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ind_off_uniform.binding = 1
	ind_off_uniform.add_id(index_offsets_buffer)

	return rd.uniform_set_create([c_uniform, ind_off_uniform], shader_prefix, 0)

func make_scatter_uniform(read_buf):
	var read_uniform = RDUniform.new()
	read_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	read_uniform.binding = 0
	read_uniform.add_id(read_buf)

	var ind_off_uniform = RDUniform.new()
	ind_off_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ind_off_uniform.binding = 1
	ind_off_uniform.add_id(index_offsets_buffer)

	var c_uniform = RDUniform.new()
	c_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	c_uniform.binding = 2
	c_uniform.add_id(count_buffer)

	var offsets_uniform = RDUniform.new()
	offsets_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	offsets_uniform.binding = 3
	offsets_uniform.add_id(offsets_buffer)

	return rd.uniform_set_create([read_uniform, ind_off_uniform, c_uniform, offsets_uniform], shader_scatter, 0)

	
