const positions = array<vec2f, 6>
(
  vec2(-1, -1),
  vec2(1, -1),
  vec2(-1, 1),

  vec2(-1, 1),
  vec2(1, -1),
  vec2(1, 1)
);

@vertex
fn main(@builtin(vertex_index) VertexIndex : u32) -> @builtin(position) vec4f
{
  return vec4(positions[VertexIndex], 1, 1);
}
