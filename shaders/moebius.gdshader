shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;

// Screen-space bande-dessinee pass: ink outlines over the scene's own colors.
//
// Drawn as a full-screen quad in the transparent pass at minimum render priority, so the two
// screen reads below hold opaque geometry alone. See MoebiusEffect for the render-order contract
// this shader depends on.

// Colour reads are filtered: the edge mask below is sampled at sub-pixel positions, and nearest
// filtering would snap every one of those back to the same texel and flatten the coverage it is
// there to measure. Depth stays nearest — an interpolated depth across a silhouette describes a
// surface that isn't there, and the normal reconstruction would fold around it.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms Ink;
uniform vec3 ink_color : source_color = vec3(0.06, 0.05, 0.08);
/// Neighbour sampling radius in pixels; doubles as line weight.
uniform float outline_thickness : hint_range(0.5, 4.0, 0.1) = 1.3;
/// Surface bend that counts as an edge, as a sine of the angle across one sample step. ~0.5 is 30
/// degrees, so flat ground stays clean while creases and silhouettes ink.
uniform float edge_threshold : hint_range(0.05, 3.0, 0.01) = 0.5;
uniform float edge_softness : hint_range(0.01, 1.0, 0.01) = 0.35;
/// Luminance-difference edges. Catches paint boundaries that lie flat on one surface — road against
/// grass — which no depth or normal test can see.
uniform float color_edge_strength : hint_range(0.0, 8.0, 0.05) = 3.0;
/// View distance, in metres, over which ink thins out to nothing. Past the far end no line is drawn
/// at all, which is what takes the ground plane's own far edge — the horizon — out of the picture.
/// It is a straight, near-horizontal, full-contrast line at the limit of the depth buffer's
/// precision, so it stairs harder than anything else on screen and carries no information worth
/// keeping. Losing distant detail to haze is also how the ink in a drawn panel behaves.
uniform float ink_fade_begin : hint_range(0.0, 500.0, 1.0) = 90.0;
uniform float ink_fade_end : hint_range(0.0, 1000.0, 1.0) = 200.0;
group_uniforms;

// Not a uniform: the inspector bakes every uniform's current value into the .tscn on save, and a
// debug view left on by an inspector save would ship silently. Edit this constant by hand instead.
// 0 final, 1 linear depth, 2 reconstructed normals, 3 edge signal.
const int DEBUG_VIEW = 0;

/// Stand-in view distance for pixels with nothing drawn in them, so a silhouette against the sky
/// reads as one enormous step rather than a division by zero.
const float SKY_DISTANCE = 4000.0;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);


bool is_sky(float raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return raw >= 0.999999;
#else
	return raw <= 0.000001;
#endif
}


// Built-ins are stage-scoped, hence inv_proj travelling by argument through everything below.
vec3 unproject(vec2 uv, float raw, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return view.xyz / view.w;
}


// View-space position under uv. Empty pixels are pushed out to SKY_DISTANCE along their own ray
// rather than left at the far plane, which keeps every caller free of a sky special case.
vec3 view_position(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_texture, uv).r;
	if (is_sky(raw)) {
		vec3 ray = unproject(uv, 0.5, inv_proj);
		return ray * (SKY_DISTANCE / max(-ray.z, 0.001));
	}
	return unproject(uv, raw, inv_proj);
}


// Ink coverage under uv, in 0..1. Also reports the reconstructed normal and view distance it
// derived on the way, which the debug views read.
//
// VIEWPORT_SIZE and the projection are fragment built-ins, so texel and inv_proj travel by argument.
float edge_at(vec2 uv, vec2 texel, float radius_scale, mat4 inv_proj, out vec3 out_normal, out float out_depth) {
	vec3 p_c = view_position(uv, inv_proj);
	vec3 p_x = view_position(uv + vec2(texel.x, 0.0), inv_proj);
	vec3 p_y = view_position(uv + vec2(0.0, texel.y), inv_proj);
	// Vertical tap before horizontal: SCREEN_UV's y runs down the screen, so p_y sits *below* p_c in
	// view space and the other ordering would face the normal away from the camera.
	out_normal = normalize(cross(p_y - p_c, p_x - p_c));
	out_depth = max(-p_c.z, 0.001);

	if (is_sky(texture(depth_texture, uv).r)) {
		return 0.0;
	}

	// View-space width of one pixel at this depth. inv_proj[0][0] is aspect * tan(fov / 2), so this
	// converts the deviations below into an angle and makes one threshold hold at every distance.
	float pixel_span = 2.0 * abs(inv_proj[0][0]) * texel.x * out_depth;
	// step_span tracks the radius actually used, so the threshold keeps meaning the same surface
	// angle no matter which ring the caller asked for.
	float radius = outline_thickness * radius_scale;
	float step_span = max(pixel_span * radius, 1.0e-6);

	vec2 offset = texel * radius;
	vec2 taps[4] = {
		vec2(-offset.x, -offset.y),
		vec2(offset.x, -offset.y),
		vec2(-offset.x, offset.y),
		vec2(offset.x, offset.y)
	};

	float bend = 0.0;
	float colour_break = 0.0;
	float centre_luma = dot(texture(screen_texture, uv).rgb, LUMA);
	for (int i = 0; i < 4; i++) {
		vec2 tap_uv = uv + taps[i];
		// Only neighbours *behind* the centre's tangent plane count, so a crease inks once, on
		// its near side, the way a pen would draw it — rather than twice, on both.
		bend = max(bend, -dot(out_normal, view_position(tap_uv, inv_proj) - p_c));
		colour_break = max(colour_break, abs(dot(texture(screen_texture, tap_uv).rgb, LUMA) - centre_luma));
	}

	float geometric = bend / step_span;
	float edge = smoothstep(edge_threshold, edge_threshold + edge_softness, geometric);
	return max(edge, smoothstep(0.5, 1.0, colour_break * color_edge_strength));
}


void vertex() {
	// Straight to clip space: the quad covers the viewport whatever the node's transform says, which
	// leaves that transform free to serve culling and sorting alone.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE;
	vec3 raw_col = texture(screen_texture, SCREEN_UV).rgb;

	bool centre_sky = is_sky(texture(depth_texture, SCREEN_UV).r);

	// The mask is read out of a nearest-filtered depth buffer, which makes it a function of integer
	// texel coordinates: it takes one value per pixel and cannot be sampled between them. Nudging the
	// sample position by a fraction of a texel returns the identical value, so the usual sub-pixel
	// supersampling buys nothing here.
	//
	// Varying the *radius* instead does move the taps onto different texels. Each ring is a dilation
	// of the silhouette by its own radius, so averaging them leaves the line solid in the core and
	// graded across its outer texel or so — a feathered edge rather than a cut one. Spacing is a
	// little over half a texel at the default thickness, which is the minimum that clears the
	// rounding boundary and actually lands on a new texel.
	float rings[4] = { 0.6, 0.85, 1.15, 1.4 };

	// Carried out of the loop for the debug views alone; the final image reads only edge.
	vec3 normal = vec3(0.0);
	float depth = 0.001;

	float edge = 0.0;
	for (int i = 0; i < 4; i++) {
		edge += edge_at(SCREEN_UV, texel, rings[i], INV_PROJECTION_MATRIX, normal, depth);
	}
	edge *= 0.25;

	// Every ring sampled SCREEN_UV, so depth is this pixel's own view distance.
	edge *= 1.0 - smoothstep(ink_fade_begin, max(ink_fade_end, ink_fade_begin + 0.001), depth);

	vec3 final_col = mix(raw_col, ink_color, edge);

	switch (DEBUG_VIEW) {
		case 1:
			final_col = vec3(fract(depth * 0.02));
			break;
		case 2:
			final_col = centre_sky ? vec3(0.0) : normal * 0.5 + 0.5;
			break;
		case 3:
			final_col = vec3(edge);
			break;
	}

	ALBEDO = final_col;
	ALPHA = 1.0;
}
