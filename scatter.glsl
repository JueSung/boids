#[compute]
#version 450

#define BOID_COUNT (1024 * 20)

#define WIDTH 32
#define HEIGHT 32

#define VIEWPORT_WIDTH (1920 * 2)
#define VIEWPORT_HEIGHT (1080 * 2)

#define WORK_GROUP_SIZE 1024

#define counts count_buffer.arr
#define index_offsets index_offsets_buffer.arr
#define offsets offsets_buffer.arr

struct Boid {
  vec2 position;
  vec2 velocity; // rotation encoded in velocity
};

layout(local_size_x = WORK_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer BoidBufferRead {
    Boid boids[BOID_COUNT];
}
boid_buffer;

layout(set = 0, binding = 1, std430) buffer IndexOffsetsBuffer {
  uint arr[WIDTH * HEIGHT];
} index_offsets_buffer;

layout(set = 0, binding = 2, std430) buffer CountBuffer {
  uint arr[WIDTH * HEIGHT];
} count_buffer;

layout(set = 0, binding = 3, std430) buffer OffsetsBuffer {
  uint arr[BOID_COUNT];
} offsets_buffer;

void main() {
  Boid me = boid_buffer.boids[gl_GlobalInvocationID.x];
  // ind for which cell this is in index_offsets_buffer
  //                                        truncates then multiply
  uint ind = uint(me.position.y / float(VIEWPORT_HEIGHT) * HEIGHT) * WIDTH + uint(me.position.x/float(VIEWPORT_WIDTH) * WIDTH);

  if (count_buffer.arr[ind] == 0) return; // shouldn't really run but just in case
  uint offset_ind = atomicAdd(count_buffer.arr[ind], -1) - 1;

  offsets[index_offsets[ind] + offset_ind] = gl_GlobalInvocationID.x;
}
