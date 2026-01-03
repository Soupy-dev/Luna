#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

vertex VertexOut vertexShader(
    uint vertexID [[vertex_id]],
    constant float *vertices [[buffer(0)]])
{
    // Vertices: position (4 floats) + texCoords (2 floats) = 6 floats per vertex
    uint offset = vertexID * 6;
    
    VertexOut out;
    out.position = float4(
        vertices[offset],
        vertices[offset + 1],
        vertices[offset + 2],
        vertices[offset + 3]
    );
    out.texCoords = float2(
        vertices[offset + 4],
        vertices[offset + 5]
    );
    
    return out;
}

fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> subtitleTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]])
{
    float4 texColor = subtitleTexture.sample(textureSampler, in.texCoords);
    
    // Preserve alpha blending for transparency
    return texColor;
}
