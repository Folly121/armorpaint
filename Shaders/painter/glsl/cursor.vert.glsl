#version 330
uniform mat4 VP;
uniform mat4 invVP;
uniform vec2 mouse;
uniform vec2 texStep;
uniform float radius;
uniform sampler2D gbufferD;
in vec4 pos;
in vec2 nor;
in vec2 tex;
out vec2 texCoord;
mat3 rotAxis(vec3 axis, float a) {
	float c = cos(a);
	vec3 as = axis * sin(a);
	mat3 p = mat3(axis.x * axis, axis.y * axis, axis.z * axis);
	mat3 q = mat3(c, -as.z, as.y, as.z, c, -as.x, -as.y, as.x, c);
	return p * (1.0 - c) + q;
}
vec3 getPos(vec2 uv) {
	float depth = textureLod(gbufferD, uv, 0.0).r;
	vec4 wpos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	wpos = invVP * wpos;
	return wpos.xyz / wpos.w;
}
vec3 getNormal(vec3 p0, vec2 uv) {
	vec3 p1 = getPos(uv + vec2(texStep.x * 4, 0));
	vec3 p2 = getPos(uv + vec2(0, texStep.y * 4));
	return normalize(cross(p2 - p0, p1 - p0));
}
void main() {
	texCoord = tex;
	vec3 wpos = getPos(mouse);
	vec2 uv1 = mouse + texStep * 4;
	vec2 uv2 = mouse - texStep * 4;
	vec3 wpos1 = getPos(uv1);
	vec3 wpos2 = getPos(uv2);
	vec3 n = normalize(
		getNormal(wpos, mouse) +
		getNormal(wpos1, uv1) +
		getNormal(wpos2, uv2)
	);
	float ax = acos(dot(vec3(1,0,0), vec3(n.x,0,0)));
	float az = acos(dot(vec3(0,0,1), vec3(0,0,n.z)));
	float sy = -sign(n.y);
	wpos +=
		rotAxis(vec3(1,0,0), -az * sy + 3.14/2) *
		rotAxis(vec3(0,0,1), ax + 3.14/2) *
		(pos.xyz * radius);
	gl_Position = VP * vec4(wpos, 1.0);
}
