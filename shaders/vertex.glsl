#version 450 core
#pragma pack_matrix(column_major)

layout(location = 0) in vec4 a_Position;

void main()
{
    gl_Position = a_Position;
}
