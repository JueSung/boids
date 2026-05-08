#[compute]
#version 450

#define WIDTH 32
#define HEIGHT 32

#define WORK_GROUP_SIZE 1024

layout(local_size_x = WORK_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer CleanBuffer {
  uint arr[WIDTH * HEIGHT];
}
clean_buffer;

void main() {
  clean_buffer.arr[gl_GlobalInvocationID.x] = 0;
}