#[compute]
#version 450

#define WIDTH 32
#define HEIGHT 32

#define WORK_GROUP_SIZE 1024


#define counts count_buffer.arr
#define index_offsets index_offsets_buffer.arr

layout(local_size_x = WORK_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer CountBuffer {
  uint arr[WIDTH * HEIGHT];
} count_buffer;

layout(set = 0, binding = 1, std430) buffer IndexOffsetsBuffer {
  uint arr[WIDTH * HEIGHT];
} index_offsets_buffer;


// implementing blelloch scan
void main() {
  // copy into index_offsets_buffer
  uint id = gl_GlobalInvocationID.x;
  
  index_offsets[id] = counts[id];
  barrier();

  // upsweep (reduce)
  for (int i = 1; i <= int(log2(float(WIDTH * HEIGHT))); i++) {
    if (id % int(1u << i) == (1u << i) - 1) {
      index_offsets[id] += index_offsets[int(id-(1u<<(i-1)))];
    }
    barrier();
  }
  if (id == WIDTH * HEIGHT-1) index_offsets[id] = 0;
  barrier();

  for (int i = int(log2(float(WIDTH * HEIGHT))); i >= 1; i--) {
    if (id % int(1u << i) == (1u << i) - 1) {
      uint temp_left = index_offsets[int(id-(1u << (i-1)))];
      index_offsets[int(id-(1u << (i-1)))] = index_offsets[id];
      index_offsets[id] += temp_left;
    }
    barrier();
  }

}