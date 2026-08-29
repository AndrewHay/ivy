class_name DevOverlayTooltips
extends RefCounted

## Short hover help for every IvyParams row in DevOverlay (W-013).

const _TIPS: Dictionary = {
	# Spec30 — growth physics
	"segment_length": "Length of each new stem piece. Shorter segments look smoother and denser; longer ones grow faster in metres but can look chunky.",
	"max_growth_rate": "Ceiling on how fast tips elongate per tick. Higher = quicker spread and fuller walls; lower = slower, sparser ivy.",
	"light_memory": "How many game-days accumulated light (D_L) remembers. Lower reacts faster to sun/shade moves; higher smooths growth and colour.",
	"light_K": "How strongly light boosts growth (Michaelis–Menten). Higher = sunny sides race ahead; lower = flatter light response.",
	"reference_DLI": "Light level treated as 'full' for growth scaling. Lower makes shade grow more; higher makes sunny spots dominate.",
	"persistence_base": "How much a tip keeps its previous direction vs turning. Higher = straighter, more committed runners; lower = wigglier stems.",
	"random_base": "Baseline random wander in growth direction. More = messier, organic paths; less = cleaner, more deliberate lines.",
	"random_new_mix": "How much fresh randomness is mixed into each direction update. Raises organic chaos without fully overriding light seeking.",
	"light_seek_min": "Minimum pull toward brighter areas. Ensures even deep shade still biases slightly toward light.",
	"light_seek_max": "Maximum light-seeking turn per step. Higher = tips bend aggressively toward sun patches and windows.",
	"adhesion_base": "Base pull to stay on the wall surface. Higher = tighter hugging; lower = looser, more floating-looking growth.",
	"adhesion_range": "Extra adhesion when close to the surface. Makes stems cling harder near contact and reduces gap-hugging.",
	"max_float": "How far a tip can hang off the wall before gravity wins. Longer runners drape and sag more dramatically.",
	"gravity_exponent": "How quickly sag ramps as floating length grows. Higher = heavier droop on overhangs and lip runners.",
	"crowding_base": "Baseline penalty when local leaf density is high. Higher = tips slow in thick mats; lower = ivy keeps packing in.",
	"crowding_decay": "How fast crowding penalty fades with distance. Lower = crowding effects linger in nearby cells.",
	"branch_rate": "Chance new side branches spawn along stems. Higher = bushier, fuller canopy; lower = fewer, straighter main runners.",
	"branch_light_exponent": "How much light boosts branching. Higher = branches prefer sunny faces; lower = more even branching.",
	"branch_crowd_exponent": "How much crowding suppresses branching. Higher = branches avoid dense mats; lower = branches in thick areas.",
	"direction_memory": "Blend of last direction vs new computed heading. Higher = smoother, less twitchy paths; lower = snappier turns.",
	"light_gradient_scale": "Strength of turning toward brighter neighbours. Higher = stronger sun-tracking and asymmetric spread.",
	"crowding_gradient_scale": "Strength of turning away from dense leaf areas. Higher = tips weave around thick patches.",
	"upward_base": "Constant upward bias while attached. Higher = stems climb more vertically; lower = flatter, wall-hugging growth.",

	# Time
	"sim_tick": "Simulation step size in game-days per tick. Normally fixed; changing it retunes all time-based behaviour.",
	"speed_watch": "Real seconds per game-day at Watch speed. Only affects playback, not final plant shape.",
	"speed_fast": "Real seconds per game-day at Fast speed. Playback only.",
	"speed_grow": "Real seconds per game-day at Grow speed. Playback only.",
	"render_sun_blend_lo": "Sun elevation (degrees) where render sun starts blending. Affects on-screen lighting smoothness at dawn/dusk.",
	"render_sun_blend_hi": "Sun elevation where render sun is fully 'day'. Higher widens the soft dawn/dusk transition.",
	"latitude": "Site latitude for solar path. Changes season length, sun height, and which wall faces get more light.",
	"longitude": "Site longitude for solar path. Shifts time-of-day sun position with latitude.",
	"day_of_year": "Calendar day for sun angle (1–365). Mid-summer = higher sun and stronger asymmetry; winter = lower, softer light.",
	"start_hour": "Clock time at simulation start (game-hours). Shifts when dawn growth bursts and diel gate readouts occur.",
	"light_warmup_days": "Days to pre-bake the light field after load/reseed. Shorter = faster start but less stable initial growth.",
	"diel_night_floor": "Minimum growth multiplier at solar midnight. Lower = almost still at night; higher = noticeable night growth.",
	"diel_exponent": "Shape of the day/night growth curve. Higher = sharper noon peak; lower = gentler day/night contrast.",
	"diel_gate_enabled": "Day/night growth gate on/off. Off = even growth all day; on = faster midday, quieter night (same daily total).",

	# Light bake
	"light_p_max": "Peak direct sun flux used in the bake. Higher = brighter sunny cells and stronger sun/shade contrast.",
	"light_p_sky": "Diffuse sky contribution. Higher = softer fill in shade and less harsh shadow edges.",
	"light_p_leak": "Ambient leak into enclosed cells (recesses). Higher = window/door pockets less dark; lower = deeper shade inside.",
	"weather_direct": "Direct sun weather multiplier (reserved). Currently pinned; changing has no effect.",
	"weather_sky": "Sky diffuse weather multiplier (reserved). Currently pinned; changing has no effect.",
	"light_elevation_exponent_direct": "How direct sun scales with elevation. Lower = more low-angle sun on walls.",
	"light_elevation_exponent_diffuse": "How sky light scales with elevation. Affects how flat overcast vs sharp sun feels.",

	# Field
	"field_cell": "Grid cell size for light and crowding fields. Finer = more detailed asymmetry; coarser = smoother, blobbier response.",
	"field_sample_jitter_ratio": "Random offset when sampling fields (× field_cell). Higher = less grid-aligned banding; lower = more regular.",
	"gradient_epsilon_ratio": "Finite-difference step for light/crowding gradients (× field_cell). Affects how sharply tips turn at boundaries.",
	"field_shell_halfwidth": "Thickness of the volumetric field shell around geometry. Wider = off-surface samples still feel the wall.",
	"vis_cell": "Coarse grid for sky-view / visibility bake. Finer = more accurate shade pockets; coarser = faster, smoother SVF.",
	"svf_rays": "Ray count per cell for sky visibility. More = cleaner shade on complex geometry; fewer = faster bake.",
	"bake_ray_length": "Max ray length in light bake. Longer = distant geometry can block sun; shorter = faster but may miss occluders.",
	"bake_ray_offset": "Surface offset when casting bake rays. Avoids self-hits; too large can miss nearby walls.",

	# Geometry
	"contact_distance": "Distance treated as 'on surface' for adhesion. Larger = sticks from farther out; smaller = must hug tighter.",
	"max_segments_per_tick": "Safety cap on segments per tip per tick. Lower = slower burst growth; higher = can spike on fast runs.",
	"branch_angle_min": "Minimum angle between parent stem and new branch. Wider = more open, fan-like structure.",
	"branch_angle_max": "Maximum branch angle from parent. Narrower range = more uniform branch geometry.",
	"branch_offset": "Spawn offset for new branches along the parent. Prevents coincident tips; tiny changes rarely visible.",
	"ground_y_min": "Minimum height for stem points. Stops ivy sinking into the ground plane.",

	# Tips
	"tip_cap_soft": "Tip count where branching starts throttling. Lower = bushiness caps sooner; higher = more tips before slowdown.",
	"tip_cap_hard": "Hard maximum live tips. Lower = sparser plant and less GPU load; higher = denser but heavier simulation.",
	"retire_margin": "Parent must beat weakest tip by this factor to branch. Higher = fewer swaps; lower = more tip churn at cap.",
	"branch_scale_floor": "Minimum branch rate when at cap. Keeps slow branching/retirement churn instead of freezing solid.",
	"stall_rate": "Daily elongation below this counts as 'stalled'. Higher = more tips go dormant in slow shade.",
	"stall_days": "Consecutive stall days before a tip sleeps. Fewer = tips give up faster in poor light.",
	"tip_cap_m1": "M1-era tip cap (not wired). Shown for reference only; changing has no effect yet.",
	"silhouette_height_frac": "Height fraction where top tips are protected from retirement. Keeps a crown on tall towers.",
	"silhouette_min_tips": "Minimum tips allowed above silhouette before retirement can cull them. Preserves lip/silhouette break.",

	# Leaf
	"internode_base": "Base spacing between leaves along a stem. Smaller = denser leaf mat; larger = airier, more stem visible.",
	"internode_shade_gain": "Extra internode length in shade. Higher = sparser leaves on dark sides (more 'balding' north face).",
	"internode_jitter": "Random variation in leaf spacing. Higher = less regular rows; lower = more uniform spacing.",
	"leaf_tip_suppress": "Reduces leaf placement near active tips. Higher = clearer growing ends; lower = leaves closer to tips.",
	"phyllotaxy_divergence": "Golden-angle spiral between leaves. Changes how leaf rows wind around the stem.",
	"phyllotaxy_flatten": "How flat the spiral is on the wall plane. Lower = more 3D twist; higher = flatter alternating rows.",
	"leaf_out_of_plane": "Tilt leaves off the wall normal. Higher = more 3D volume and depth; lower = flatter wall carpet.",
	"leaf_photo_cant": "Leaves tilt toward light. Higher = sunnier leaves face the sky more (stronger sun/shade read).",
	"droop_base": "Base leaf droop angle in degrees. Higher = leaves hang down more everywhere.",
	"droop_shade_gain": "Extra droop in shade. Higher = shaded leaves droop more than sunlit ones.",
	"leaf_jitter_tilt": "Random tilt variation about the petiole axis (degrees). Breaks up uniform planes.",
	"leaf_jitter_roll": "Random roll about the blade long axis (degrees).",
	"leaf_jitter_yaw": "Random yaw about the petiole axis (degrees).",
	"leaf_offset_base": "Push leaves off the stem surface. Higher = less z-fighting; lower = tighter to wall.",
	"leaf_offset_step": "Extra offset per ladder step when leaves overlap. Keeps stacks from coplanar flicker.",
	"leaf_offset_ladder": "How many offset steps before resetting. Affects how deep overlapping leaves sit.",
	"leaf_width_base": "Base leaf card width. Larger = bolder, coarser texture; smaller = finer, lacy ivy.",
	"leaf_order_falloff": "Size reduction on higher branch orders. Higher = smaller leaves on twigs.",
	"leaf_expand_distance": "Distance-based leaf expansion (not wired). Would swell leaves away from anchors.",
	"leaf_light_scale_base": "Minimum rendered leaf size from light. Floors how small sun leaves can look.",
	"leaf_light_scale_gain": "How much light enlarges leaves. Higher = sun leaves noticeably bigger (presentation only).",
	"leaf_size_sigma": "Random leaf size spread (log-normal sigma). Higher = more size variety between leaves.",
	"leaf_healthy_base": "Baseline chance of healthy (green) leaf tier. Higher = fewer weathered/speckled leaves overall.",
	"leaf_healthy_gain": "How much light pushes healthy tier. Higher = sun leaves greener; shade can stay weathered.",
	"leaf_weathered_tint": "Color multiplier on weathered-tier leaves. Lower red / higher green cools autumn-like atlas speckle.",
	"leaf_shade_tint": "Colour multiplier for shaded leaves. Cooler/darker = more muted north side; warmer = less contrast.",
	"leaf_sun_tint": "Colour multiplier for sunlit leaves. Warmer/brighter = sunnier read on south face.",
	"leaf_crowd_suppress": "How strongly high crowding blocks new leaves. Higher = thinner mats in dense zones.",
	"leaf_crowd_floor": "Minimum leaf placement chance even in dense crowding. Prevents total bald patches in thick growth.",
	"leaf_crowd_k": "How much each leaf deposits into the crowding field. Higher = faster self-thinning in thick areas.",
	"leaf_cap": "Maximum leaf instances. Lower = lighter render and sparser plant; higher = denser but costlier.",

	# Stem render
	"stem_radius_base": "Rendered stem tube radius. Thicker = woodier look; thinner = delicate vines.",
	"stem_order_falloff": "Stem thinning on higher branch orders. Higher = thinner twigs on side branches.",
	"stem_tip_taper": "Metres of shoot over which stems narrow toward the tip. Lower = sharper points.",
}


static func for_param(param_name: String, inert: bool = false) -> String:
	var tip: String = _TIPS.get(param_name, "")
	if tip.is_empty():
		return "No description yet for this parameter."
	if inert:
		return tip + " (Not wired in simulation yet — changing this has no effect.)"
	return tip
