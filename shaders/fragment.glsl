#version 450 core
#pragma pack_matrix(column_major)

layout(location = 0) out vec4 o_Color;

layout(set = 0, binding = 0) uniform texture2D u_Texture;
layout(set = 0, binding = 1) uniform sampler u_Sampler;

layout(push_constant) uniform PushConstants {
    vec2 u_TextureSize;
    float u_Scale;
};

void main()
{
    vec2 uv = (floor(gl_FragCoord.xy / u_Scale) + 0.5) / u_TextureSize;

    o_Color = texture(sampler2D(u_Texture, u_Sampler), uv);
    o_Color = vec4(1.0);
}
