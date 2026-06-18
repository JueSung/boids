#[compute]
#version 450

#define BOID_COUNT (1024 * 20)

#define WIDTH 32
#define HEIGHT 32

#define VIEWPORT_WIDTH (1920 * 2)
#define VIEWPORT_HEIGHT (1080 * 2)

#define WORK_GROUP_SIZE 1024

#define CELL_HEIGHT (float(VIEWPORT_WIDTH) / WIDTH)
#define CELL_WIDTH (float(VIEWPORT_HEIGHT) / HEIGHT)

#define ZERO_TOLERANCE 1e-3

struct Boid {
  vec2 position;
  vec2 velocity; // rotation encoded in velocity
};

layout(local_size_x = WORK_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer BoidBufferRead {
    Boid boids[BOID_COUNT];
}
boidBufferRead;

layout(set = 0, binding = 2, std430) buffer BoidBufferWrite {
    Boid boids[BOID_COUNT];
}
boidBufferWrite;

layout(set = 0, binding = 1, std140) uniform Params {
    float delta;
    uint boid_count;
		float cohesion_factor;
		float alignment_factor;
		float separation_factor;
		float turn_speed;
		float neighbor_radius;
		float separation_radius;
		float speed;
} params;

layout(set = 0, binding = 3, std430) buffer IndexOffsetsBuffer {
	uint arr[WIDTH * HEIGHT];
} indexOffsetsBuffer;

layout(set = 0, binding = 4, std430) buffer OffsetsBuffer {
	uint arr[BOID_COUNT];
} offsetsBuffer;

layout(set = 0, binding = 5, std430) buffer TransformBuffer {
	float arr[BOID_COUNT * 8];
} transform_buffer;


void main() {
	uint id = gl_GlobalInvocationID.x;
	if (id >= params.boid_count) return;

	Boid me = boidBufferRead.boids[id];
	vec2 me_vel_norm = length(me.velocity) < ZERO_TOLERANCE ? me.velocity : normalize(me.velocity);

	// int NEIGHBOR_RADIUS = 80; // dist for neighbors to contribute at all - will be replaced by grid thing
	// int SEPARATION_RADIUS = 40; // dist for separation to play a role

	// int NEIGHBOR_CELL_RADIUS = 2;
	int NEIGHBOR_CELL_RADIUS_HEIGHT = int((params.neighbor_radius + CELL_HEIGHT - 1)/ CELL_HEIGHT);
	int NEIGHBOR_CELL_RADIUS_WIDTH = int((params.neighbor_radius + CELL_WIDTH - 1)/ CELL_WIDTH);
	ivec2 me_cell_pos = ivec2(int(me.position.x/float(VIEWPORT_WIDTH) * WIDTH), int(me.position.y / float(VIEWPORT_HEIGHT) * HEIGHT));

	vec2 cohesion = vec2(0,0);
	vec2 separation = vec2(0,0);
	vec2 alignment = vec2(0,0);
	uint neighbors = 0;
	for (int row = me_cell_pos.y - NEIGHBOR_CELL_RADIUS_HEIGHT; row <= me_cell_pos.y + NEIGHBOR_CELL_RADIUS_HEIGHT; row+= 1) {
		if (row < 0 || row >= HEIGHT) continue;
		for (int col = me_cell_pos.x - NEIGHBOR_CELL_RADIUS_WIDTH; col <= me_cell_pos.x + NEIGHBOR_CELL_RADIUS_WIDTH; col+= 1) {
			if (col < 0 || col >= WIDTH) continue;
			
			int cell_ind = row * WIDTH + col;
			uint offset_ind = indexOffsetsBuffer.arr[cell_ind];
			uint cell_boid_count = 0;
			if (cell_ind != WIDTH * HEIGHT - 1) {
				cell_boid_count = indexOffsetsBuffer.arr[cell_ind+1] - offset_ind;
			}
			else cell_boid_count = params.boid_count - offset_ind;
			
			for (uint i = 0; i < cell_boid_count; i+= 1) {
				//if (offset_ind>= params.boid_count) break;
				uint j = offsetsBuffer.arr[offset_ind+i];
				if (j == id) continue; // self


				vec2 other_pos = boidBufferRead.boids[j].position;
				vec2 dist = other_pos - me.position;

				float dist_len = length(dist);
				// 
				if (dist_len > params.neighbor_radius || acos(clamp(dot(normalize(dist), me_vel_norm), -1, 1)) > 2 * 3.1415 / 3) continue;

				neighbors += 1;

				cohesion += other_pos;
				alignment += (boidBufferRead.boids[j].velocity-me.velocity);

				if (dist_len > params.separation_radius) continue;
				
				separation -= (dist) / pow(max(dist_len, 0.0001), 3.2);
			}

		}
	}
	// for (int i = 0; i < params.boid_count; i++) {
	// 	if (id == i) continue;
	// 	vec2 other_pos = boidBufferRead.boids[i].position;
	// 	vec2 dist = other_pos - me.position;
	// 	if (length(dist) > NEIGHBOR_RADIUS || acos(dot(normalize(dist), normalize(me.velocity))) > 2 * 3.1415 / 3) continue;
	// 	neighbors += 1;
	// 	cohesion += other_pos;
	// 	alignment += (boidBufferRead.boids[i].velocity-me.velocity);

	// 	if (length(dist) > SEPARATION_RADIUS) continue;
	// 	separation -= (dist) / pow(max(length(dist), 0.0001), 2);
	
	// }
	
	// const float ACCELERATION = 1000; // whatever that means;

	vec2 new_vel = params.speed * me_vel_norm;
	// me.velocity = vec2(0,0);
	if (neighbors != 0) {
		vec2 cohesion_dir = normalize(cohesion/float(neighbors) - me.position);
		vec2 alignment_dir = normalize(alignment);
		
		//////////////////////////////////////////////////////////////////////////////////////////////////
		// this line to tweak balancing-------------------------------------------------------------------
		//////////////////////////////////////////////////////////////////////////////////////////////////
		vec2 target_vel = params.speed * normalize(params.cohesion_factor * cohesion_dir + params.alignment_factor * alignment_dir + params.separation_factor * separation);
		//////////////////////////////////////////////////////////////////////////////////////////////////
		//------------------------------------------------------------------------------------------------
		//////////////////////////////////////////////////////////////////////////////////////////////////
		
		vec2 me_norm_vel = length(me.velocity) < ZERO_TOLERANCE ? me.velocity : normalize(me.velocity);
		vec2 target_norm_vel = length(target_vel) < ZERO_TOLERANCE ? target_vel : normalize(target_vel);
		
		vec2 temp_new_vel = mix(me_norm_vel, target_norm_vel, clamp(params.turn_speed * params.delta, 0.0, 1.0));
		new_vel = (length(temp_new_vel) < ZERO_TOLERANCE ? temp_new_vel : normalize(temp_new_vel)) * params.speed;
	}

	boidBufferWrite.boids[id].velocity = new_vel;//length(target_vel - me.velocity) < ACCELERATION * params.delta ? target_vel : me.velocity + ACCELERATION * normalize(target_vel) * params.delta;
	boidBufferWrite.boids[id].position = boidBufferRead.boids[id].position + boidBufferWrite.boids[id].velocity * params.delta;

	boidBufferWrite.boids[id].position = mod(boidBufferWrite.boids[id].position, vec2(VIEWPORT_WIDTH, VIEWPORT_HEIGHT));

	int base = int(id * 8);

	float c = transform_buffer.arr[base + 0]; // initalize to previous orientation
	float s = transform_buffer.arr[base + 4];
	if (length(new_vel) > ZERO_TOLERANCE) {
		c = new_vel.x / length(new_vel);
		s = new_vel.y / length(new_vel);
	}

	
	transform_buffer.arr[base + 0] = c;
	transform_buffer.arr[base + 1] = -s;
	transform_buffer.arr[base + 2] = 0;
	transform_buffer.arr[base + 3] = boidBufferWrite.boids[id].position.x;
	transform_buffer.arr[base + 4] = s;
	transform_buffer.arr[base + 5] = c;
	transform_buffer.arr[base + 6] = 0;
	transform_buffer.arr[base + 7] = boidBufferWrite.boids[id].position.y;

}