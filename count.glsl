#[compute]
#version 450

#define BOID_COUNT (1024 * 20)

#define WIDTH 32
#define HEIGHT 32

#define VIEWPORT_WIDTH (1920 * 2)
#define VIEWPORT_HEIGHT (1080 * 2)

#define WORK_GROUP_SIZE 1024

struct Boid {
  vec2 position;
  vec2 velocity; // rotation encoded in velocity
};

layout(local_size_x = WORK_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 1, std430) buffer CountBuffer {
  uint arr[WIDTH * HEIGHT];
} count_buffer;

layout(set = 0, binding = 0, std430) buffer BoidBuffer {
  Boid boids[BOID_COUNT];
} boidBuffer;

void main() {
  // calculate index based on position
  Boid me = boidBuffer.boids[gl_GlobalInvocationID.x];
  //                                        truncates then multiply
  uint ind = uint(me.position.y / float(VIEWPORT_HEIGHT) * HEIGHT) * WIDTH + uint(me.position.x/float(VIEWPORT_WIDTH) * WIDTH);
  atomicAdd(count_buffer.arr[ind], 1);
}