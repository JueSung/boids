#[compute]
#version 450


struct Boid {
  vec2 position;
  vec2 velocity; // rotation encoded in velocity
};

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer BoidBufferRead {
    Boid boids[1024 * 5];
}
boidBufferRead;

layout(set = 0, binding = 2, std430) buffer BoidBufferWrite {
    Boid boids[1024 * 5];
}
boidBufferWrite;

layout(set = 0, binding = 1, std140) uniform Params {
    float delta;
    uint boid_count;
} params;

void main() {
	uint id = gl_GlobalInvocationID.x;
	if (id >= params.boid_count) return;

	Boid me = boidBufferRead.boids[id];

	int NEIGHBOR_RADIUS = 80; // dist for neighbors to contribute at all - will be replaced by grid thing
	int SEPARATION_RADIUS = 40; // dist for separation to play a role

	vec2 cohesion = vec2(0,0);
	vec2 separation = vec2(0,0);
	vec2 alignment = vec2(0,0);
	uint neighbors = 0;
	for (int i = 0; i < params.boid_count; i++) {
		if (id == i) continue;
		vec2 other_pos = boidBufferRead.boids[i].position;
		vec2 dist = other_pos - me.position;
		if (length(dist) > NEIGHBOR_RADIUS || acos(dot(normalize(dist), normalize(me.velocity))) > 2 * 3.1415 / 3) continue;
		neighbors += 1;
		cohesion += other_pos;
		alignment += (boidBufferRead.boids[i].velocity-me.velocity);

		if (length(dist) > SEPARATION_RADIUS) continue;
		separation -= (dist) / pow(max(length(dist), 0.0001), 2);
	
	}
	
	vec2 new_vel = me.velocity;
	if (neighbors != 0) {
		const float SPEED = 300;
		// const float ACCELERATION = 1000; // whatever that means
		const float TURN_SPEED = 3;

		vec2 cohesion_dir = normalize(cohesion/float(neighbors) - me.position);
		vec2 alignment_dir = normalize(alignment);
		
		
		vec2 target_vel = SPEED * normalize(.72 * cohesion_dir + 0.7 * alignment_dir + 6 * separation);
		
		//float rot = atan(me.velocity.y, me.velocity.x) + (target_vel.x * me.velocity.y - target_vel.y * me.velocity.x < 0 ? 1 : -1) * TURN_SPEED * params.delta;
		new_vel = normalize(mix(normalize(me.velocity), normalize(target_vel), clamp(TURN_SPEED * params.delta, 0.0, 1.0))) * SPEED; //SPEED * vec2(cos(rot), sin(rot));
	}

	boidBufferWrite.boids[id].velocity = new_vel;//length(target_vel - me.velocity) < ACCELERATION * params.delta ? target_vel : me.velocity + ACCELERATION * normalize(target_vel) * params.delta;
	boidBufferWrite.boids[id].position = boidBufferRead.boids[id].position + boidBufferWrite.boids[id].velocity * params.delta;

	boidBufferWrite.boids[id].position = mod(boidBufferWrite.boids[id].position, vec2(1920, 1080));
	
	
}