/*
	* Procedural Frontier
	*
	* A single all-cave map generated from a landmark. The generator is arranged
	* as independent stages so terrain, landmarks, or landing-zone rules can be
	* replaced without rewriting the complete generation pass.
	*/

/area/procedural_frontier
	name = "Frontier Caves"
	icon_state = "red"
	ceiling = CEILING_DEEP_UNDERGROUND
	outside = FALSE
	always_unpowered = TRUE
	minimap_color = MINIMAP_AREA_CAVES

/area/procedural_frontier/landing
	name = "Landing Zone"
	icon_state = "green"
	minimap_color = MINIMAP_AREA_LZ

/area/procedural_frontier/landing/lz1
	name = "Landing Zone One"
	icon_state = "away1"
	area_flags = NONE

// All coordinates derived for one map-generation run.
/datum/procedural_frontier_layout
	var/z_level
	var/map_min_x
	var/map_max_x
	var/map_min_y
	var/map_max_y
	var/map_center_x
	var/map_center_y
	var/landing_min_x
	var/landing_max_x
	var/landing_min_y
	var/landing_max_y
	var/landing_center_x
	var/landing_center_y
	var/pad_min_x
	var/pad_max_x
	var/pad_min_y
	var/pad_max_y
	var/max_landing_distance
	var/landing_edge_factor

/datum/procedural_frontier_layout/proc/is_border(x, y)
	return x == map_min_x || x == map_max_x || y == map_min_y || y == map_max_y

/datum/procedural_frontier_layout/proc/is_landing(x, y)
	return x >= landing_min_x && x <= landing_max_x && y >= landing_min_y && y <= landing_max_y

/datum/procedural_frontier_layout/proc/is_landing_border(x, y)
	return is_landing(x, y) && (x == landing_min_x || x == landing_max_x || y == landing_min_y || y == landing_max_y)

/datum/procedural_frontier_layout/proc/is_pad(x, y)
	return x >= pad_min_x && x <= pad_max_x && y >= pad_min_y && y <= pad_max_y

/datum/procedural_frontier_layout/proc/get_landing_center()
	return locate(landing_center_x, landing_center_y, z_level)

// Deterministic value noise helpers. Keep these global for use by future map
// features (for example ore veins or a distinct cave-biome pass).
/proc/procedural_frontier_hash(x, y, seed)
	var/value = sin((x * 12.9898) + (y * 78.233) + (seed * 0.001)) * 43758.5453
	return value - floor(value)

/proc/procedural_frontier_fade(value)
	return value * value * value * (value * (value * 6 - 15) + 10)

/proc/procedural_frontier_value_noise(x, y, seed, grid_scale)
	var/grid_x = floor(x / grid_scale)
	var/grid_y = floor(y / grid_scale)
	var/fraction_x = (x / grid_scale) - grid_x
	var/fraction_y = (y / grid_scale) - grid_y
	var/smooth_x = procedural_frontier_fade(fraction_x)
	var/smooth_y = procedural_frontier_fade(fraction_y)
	var/noise_bottom_left = procedural_frontier_hash(grid_x, grid_y, seed)
	var/noise_bottom_right = procedural_frontier_hash(grid_x + 1, grid_y, seed)
	var/noise_top_left = procedural_frontier_hash(grid_x, grid_y + 1, seed)
	var/noise_top_right = procedural_frontier_hash(grid_x + 1, grid_y + 1, seed)
	var/low_edge = noise_bottom_left + (noise_bottom_right - noise_bottom_left) * smooth_x
	var/high_edge = noise_top_left + (noise_top_right - noise_top_left) * smooth_x
	return low_edge + (high_edge - low_edge) * smooth_y

/proc/procedural_frontier_noise(x, y, seed, coarse_scale = 16, fine_scale = 5, coarse_weight = 0.70)
	var/coarse_noise = procedural_frontier_value_noise(x, y, seed, coarse_scale)
	var/fine_noise = procedural_frontier_value_noise(x, y, seed + 31, fine_scale)
	return coarse_noise * coarse_weight + fine_noise * (1 - coarse_weight)

/proc/procedural_frontier_ridge_noise(x, y, seed, coarse_scale = 16, fine_scale = 5, coarse_weight = 0.70)
	var/value = procedural_frontier_noise(x, y, seed, coarse_scale, fine_scale, coarse_weight)
	return 1 - abs((value * 2) - 1)

// Normalized exponential ease-out: 0 at the landing, 1 at the farthest edge.
/proc/procedural_frontier_landing_threshold(distance, max_distance, exponential_rate)
	if(max_distance <= 0)
		return 1
	var/normalized_distance = clamp(distance / max_distance, 0, 1)
	var/rate = max(0.01, exponential_rate)
	var/normalizer = 1 - (2 ** (-rate))
	if(!normalizer)
		return normalized_distance
	return clamp((1 - (2 ** (-rate * normalized_distance))) / normalizer, 0, 1)

/obj/effect/landmark/procedural_frontier_generator
	name = "Procedural Frontier generator"
	icon_state = "x2"

	// Map dimensions must match the authored .dmm shell.
	var/map_width = 199
	var/map_height = 199

	// Landing zone geometry and placement.
	var/landing_width = 20
	var/landing_height = 30
	var/landing_edge_margin = 8
	var/landing_exit_length = 18
	var/pad_width = 11
	var/pad_height = 21

	// Cave-density profile. The LZ surface is always open; farther away, the
	// ridge cutoff rises according to the exponential gradient.
	var/landing_surface_radius = 24
	var/landing_edge_opening = 4.0
	var/remote_cave_cutoff = 0.82
	var/cave_ridge_threshold = 0.0
	var/central_landing_complexity = 0.18
	// A hard ridge check selects solid material eligible for deep walls. The
	// separate wall-distance test below ensures these are not cave boundaries.
	var/hard_ridge_cutoff = 0.35
	var/deep_wall_separation = 2
	var/deep_cave_wall_type = /turf/closed/wall/r_wall

	// Noise settings. Expose both layers to make biome-specific generators easy.
	var/noise_coarse_scale = 16
	var/noise_fine_scale = 5
	var/noise_coarse_weight = 0.70

	// Landmark placement settings.
	var/weed_node_spacing = 5
	var/tunnel_edge_offset = 10
	var/tunnel_minimum_spacing = 24
	var/miner_platinum_count = 16
	var/xenomorph_spawn_count = 3
	var/excavation_site_count = 20

/obj/effect/landmark/procedural_frontier_generator/Initialize(mapload)
	. = ..()
	if(!mapload)
		return
	generate()
	return INITIALIZE_HINT_QDEL

/obj/effect/landmark/procedural_frontier_generator/proc/generate()
	var/seed = Master.random_seed
	var/datum/procedural_frontier_layout/layout = create_layout(seed)
	if(!layout)
		return
	var/area/cave_area = new /area/procedural_frontier
	var/area/landing_area = new /area/procedural_frontier/landing/lz1

	generate_terrain(layout, cave_area, landing_area, seed)
	carve_landing_exit(layout, cave_area, landing_area)
	place_landing_docking_port(layout)
	place_deep_walls(layout, cave_area, seed)
	var/list/open_cave_tiles = retain_reachable_cave_tiles(layout, cave_area, landing_area)
	place_weed_nodes(open_cave_tiles)
	place_xeno_tunnels(open_cave_tiles, layout)
	place_platinum_landmarks(open_cave_tiles)
	place_xenomorph_spawns(open_cave_tiles)
	place_excavation_sites(open_cave_tiles, layout)

	smooth_zlevel(layout.z_level)
	log_game("Procedural Frontier caves generated: [map_width]x[map_height], landing at ([layout.landing_center_x],[layout.landing_center_y]), seed [seed]")

/obj/effect/landmark/procedural_frontier_generator/proc/create_layout(seed)
	var/datum/procedural_frontier_layout/layout = new
	layout.z_level = z
	// The landmark is the authored map center. This makes the runtime map
	// independent of the z-level's world origin.
	layout.map_center_x = x
	layout.map_center_y = y
	layout.map_min_x = layout.map_center_x - round((map_width - 1) / 2)
	layout.map_min_y = layout.map_center_y - round((map_height - 1) / 2)
	layout.map_max_x = layout.map_min_x + map_width - 1
	layout.map_max_y = layout.map_min_y + map_height - 1

	var/available_x = max(1, map_width - landing_width - landing_edge_margin * 2)
	var/available_y = max(1, map_height - landing_height - landing_edge_margin * 2)
	layout.landing_min_x = layout.map_min_x + landing_edge_margin + round(procedural_frontier_hash(701, 17, seed) * available_x)
	layout.landing_min_y = layout.map_min_y + landing_edge_margin + round(procedural_frontier_hash(719, 23, seed) * available_y)
	layout.landing_max_x = layout.landing_min_x + landing_width - 1
	layout.landing_max_y = layout.landing_min_y + landing_height - 1
	layout.landing_center_x = round((layout.landing_min_x + layout.landing_max_x) / 2)
	layout.landing_center_y = round((layout.landing_min_y + layout.landing_max_y) / 2)
	layout.pad_min_x = layout.landing_center_x - round((pad_width - 1) / 2)
	layout.pad_max_x = layout.pad_min_x + pad_width - 1
	layout.pad_min_y = layout.landing_center_y - round((pad_height - 1) / 2)
	layout.pad_max_y = layout.pad_min_y + pad_height - 1
	layout.max_landing_distance = get_farthest_edge_distance(layout)
	layout.landing_edge_factor = get_landing_edge_factor(layout)
	return layout

/obj/effect/landmark/procedural_frontier_generator/proc/get_farthest_edge_distance(datum/procedural_frontier_layout/layout)
	var/turf/landing_center = layout.get_landing_center()
	if(!landing_center)
		return 1
	var/farthest_distance = 1
	for(var/list/corner in list(
		list(layout.map_min_x, layout.map_min_y),
		list(layout.map_max_x, layout.map_min_y),
		list(layout.map_min_x, layout.map_max_y),
		list(layout.map_max_x, layout.map_max_y),
	))
		var/turf/corner_turf = locate(corner[1], corner[2], layout.z_level)
		if(corner_turf)
			farthest_distance = max(farthest_distance, get_dist(landing_center, corner_turf))
	return farthest_distance

/obj/effect/landmark/procedural_frontier_generator/proc/get_landing_edge_factor(datum/procedural_frontier_layout/layout)
	var/relative_x = abs(layout.landing_center_x - layout.map_center_x) / max(1, map_width / 2)
	var/relative_y = abs(layout.landing_center_y - layout.map_center_y) / max(1, map_height / 2)
	return clamp(max(relative_x, relative_y), 0, 1)

/obj/effect/landmark/procedural_frontier_generator/proc/generate_terrain(datum/procedural_frontier_layout/layout, area/cave_area, area/landing_area, seed)
	var/turf/landing_center = layout.get_landing_center()
	var/central_complexity_multiplier = 1 + central_landing_complexity * (1 - layout.landing_edge_factor)
	for(var/tile_x in layout.map_min_x to layout.map_max_x)
		for(var/tile_y in layout.map_min_y to layout.map_max_y)
			var/turf/current_turf = locate(tile_x, tile_y, layout.z_level)
			if(!current_turf)
				continue
			if(layout.is_landing(tile_x, tile_y))
				if(layout.is_landing_border(tile_x, tile_y))
					set_turf_and_area(current_turf, /turf/closed/wall/r_wall, landing_area)
				else if(layout.is_pad(tile_x, tile_y))
					set_turf_and_area(current_turf, /turf/open/floor/plating, landing_area)
				else
					set_turf_and_area(current_turf, /turf/open/floor/plating/ground/mars, landing_area)
				continue
			if(layout.is_border(tile_x, tile_y))
				set_turf_and_area(current_turf, /turf/closed/mineral/smooth/bigred/indestructible, cave_area)
				continue
			var/distance_from_landing = landing_center ? get_dist(current_turf, landing_center) : 0
			if(distance_from_landing <= landing_surface_radius)
				set_turf_and_area(current_turf, /turf/open/floor/plating/ground/mars/random/dirt, cave_area)
				continue
			var/ridge_cutoff = get_ridge_cutoff(distance_from_landing, layout, central_complexity_multiplier)
			var/ridge_value = procedural_frontier_ridge_noise(tile_x, tile_y, seed, noise_coarse_scale, noise_fine_scale, noise_coarse_weight)
			if(ridge_value >= ridge_cutoff)
				set_turf_and_area(current_turf, /turf/open/floor/plating/ground/mars/random/cave, cave_area)
			else
				set_turf_and_area(current_turf, /turf/closed/mineral/smooth/bigred, cave_area)

/obj/effect/landmark/procedural_frontier_generator/proc/get_ridge_cutoff(distance_from_landing, datum/procedural_frontier_layout/layout, central_complexity_multiplier)
	var/distance_threshold = procedural_frontier_landing_threshold(distance_from_landing, layout.max_landing_distance, landing_edge_opening)
	return clamp(distance_threshold * remote_cave_cutoff * central_complexity_multiplier + cave_ridge_threshold, 0, 1)

/obj/effect/landmark/procedural_frontier_generator/proc/set_turf_and_area(turf/target_turf, turf_type, area/target_area)
	var/turf/new_turf = target_turf.ChangeTurf(turf_type, null, CHANGETURF_SKIP)
	new_turf.change_area(new_turf.loc, target_area)
	return new_turf

/obj/effect/landmark/procedural_frontier_generator/proc/carve_landing_exit(datum/procedural_frontier_layout/layout, area/cave_area, area/landing_area)
	var/list/exit_centers = list(layout.landing_min_x + 6, layout.landing_max_x - 6)
	for(var/exit_center_x in exit_centers)
		for(var/exit_x in exit_center_x - 1 to exit_center_x + 1)
			for(var/exit_y = layout.landing_min_y - 1, exit_y >= max(layout.map_min_y + 1, layout.landing_min_y - landing_exit_length), exit_y--)
				var/turf/exit_turf = locate(exit_x, exit_y, layout.z_level)
				if(exit_turf)
					set_turf_and_area(exit_turf, /turf/open/floor/plating/ground/mars/random/cave, cave_area)
	// Remove the two three-tile sections from the south wall after carving.
	for(var/exit_center_x in exit_centers)
		for(var/exit_x in exit_center_x - 1 to exit_center_x + 1)
			var/turf/wall_gap = locate(exit_x, layout.landing_min_y, layout.z_level)
			if(wall_gap)
				set_turf_and_area(wall_gap, /turf/open/floor/plating, landing_area)

/obj/effect/landmark/procedural_frontier_generator/proc/place_landing_docking_port(datum/procedural_frontier_layout/layout)
	var/turf/landing_center = layout.get_landing_center()
	if(landing_center)
		var/obj/docking_port/stationary/marine_dropship/lz1/docking_port = new(landing_center)
		docking_port.area_type = /area/procedural_frontier/landing/lz1
	// The button is mounted on the inner side of the west wall.
	var/turf/button_turf = locate(layout.landing_min_x + 1, layout.landing_center_y, layout.z_level)
	if(button_turf)
		new /obj/machinery/button/door/open_only/landing_zone(button_turf)

/obj/effect/landmark/procedural_frontier_generator/proc/place_deep_walls(datum/procedural_frontier_layout/layout, area/cave_area, seed)
	// Deep walls are based on separation from open cave tiles, never on LZ
	// distance. This keeps r_walls in the interior of thick rock masses.
	for(var/tile_x in layout.map_min_x + 1 to layout.map_max_x - 1)
		for(var/tile_y in layout.map_min_y + 1 to layout.map_max_y - 1)
			var/turf/rock_turf = locate(tile_x, tile_y, layout.z_level)
			if(!rock_turf || !istype(rock_turf, /turf/closed/mineral/smooth/bigred))
				continue
			var/ridge_value = procedural_frontier_ridge_noise(tile_x, tile_y, seed, noise_coarse_scale, noise_fine_scale, noise_coarse_weight)
			if(ridge_value > hard_ridge_cutoff || !is_deep_inside_rock(rock_turf, layout))
				continue
			set_turf_and_area(rock_turf, deep_cave_wall_type, cave_area)

/obj/effect/landmark/procedural_frontier_generator/proc/is_deep_inside_rock(turf/rock_turf, datum/procedural_frontier_layout/layout)
	for(var/offset_x in -deep_wall_separation to deep_wall_separation)
		for(var/offset_y in -deep_wall_separation to deep_wall_separation)
			if(!offset_x && !offset_y)
				continue
			var/turf/neighbor = locate(rock_turf.x + offset_x, rock_turf.y + offset_y, layout.z_level)
			if(!neighbor || istype(neighbor, /turf/open))
				return FALSE
	return TRUE

/obj/effect/landmark/procedural_frontier_generator/proc/retain_reachable_cave_tiles(datum/procedural_frontier_layout/layout, area/cave_area, area/landing_area)
	// Flood-fill starts inside the LZ. Any open cave tile which cannot be reached
	// cardinally from it is sealed back into rock before landmarks are placed.
	var/turf/landing_center = layout.get_landing_center()
	if(!landing_center)
		return list()
	var/list/reachable_tiles = list()
	var/list/visited = list()
	var/list/queue = list(landing_center)
	var/queue_index = 1
	while(queue_index <= length(queue))
		var/turf/current_turf = queue[queue_index++]
		var/current_key = "[current_turf.x],[current_turf.y]"
		if(visited[current_key])
			continue
		visited[current_key] = TRUE
		if(!istype(current_turf, /turf/open))
			continue
		for(var/direction in GLOB.cardinals)
			var/turf/neighbor = get_step(current_turf, direction)
			if(!neighbor)
				continue
			if(neighbor.x <= layout.map_min_x || neighbor.x >= layout.map_max_x || neighbor.y <= layout.map_min_y || neighbor.y >= layout.map_max_y)
				continue
			var/neighbor_key = "[neighbor.x],[neighbor.y]"
			if(!visited[neighbor_key] && istype(neighbor, /turf/open))
				queue += neighbor

	for(var/tile_x in layout.map_min_x + 1 to layout.map_max_x - 1)
		for(var/tile_y in layout.map_min_y + 1 to layout.map_max_y - 1)
			var/turf/cave_turf = locate(tile_x, tile_y, layout.z_level)
			if(!cave_turf || layout.is_landing(tile_x, tile_y))
				continue
			var/cave_key = "[tile_x],[tile_y]"
			if(istype(cave_turf, /turf/open) && visited[cave_key])
				reachable_tiles += cave_turf
			else if(istype(cave_turf, /turf/open))
				set_turf_and_area(cave_turf, /turf/closed/mineral/smooth/bigred, cave_area)
	return reachable_tiles

/obj/effect/landmark/procedural_frontier_generator/proc/place_weed_nodes(list/open_cave_tiles)
	for(var/turf/cave_turf in open_cave_tiles)
		if(cave_turf.x % weed_node_spacing == 0 && cave_turf.y % weed_node_spacing == 0)
			new /obj/effect/landmark/weed_node(cave_turf)

/obj/effect/landmark/procedural_frontier_generator/proc/place_xeno_tunnels(list/open_cave_tiles, datum/procedural_frontier_layout/layout)
	var/list/tunnel_tiles = list()
	var/list/tunnel_targets = list(
		list(layout.map_min_x + tunnel_edge_offset, layout.map_min_y + tunnel_edge_offset),
		list(layout.map_max_x - tunnel_edge_offset, layout.map_min_y + tunnel_edge_offset),
		list(layout.map_min_x + tunnel_edge_offset, layout.map_max_y - tunnel_edge_offset),
		list(layout.map_max_x - tunnel_edge_offset, layout.map_max_y - tunnel_edge_offset),
	)
	for(var/list/target in tunnel_targets)
		var/turf/best_tunnel_turf = get_best_tunnel_tile(open_cave_tiles, tunnel_tiles, target)
		if(best_tunnel_turf)
			new /obj/effect/landmark/xeno_tunnel_spawn(best_tunnel_turf)
			tunnel_tiles += best_tunnel_turf

/obj/effect/landmark/procedural_frontier_generator/proc/get_best_tunnel_tile(list/open_cave_tiles, list/placed_tunnels, list/target)
	var/turf/best_tunnel_turf
	var/best_score = INFINITY
	for(var/turf/cave_turf in open_cave_tiles)
		if(!is_tunnel_tile_far_enough(cave_turf, placed_tunnels))
			continue
		var/score = abs(cave_turf.x - target[1]) + abs(cave_turf.y - target[2])
		if(score < best_score)
			best_score = score
			best_tunnel_turf = cave_turf
	return best_tunnel_turf

/obj/effect/landmark/procedural_frontier_generator/proc/is_tunnel_tile_far_enough(turf/candidate, list/placed_tunnels)
	for(var/turf/other_tunnel in placed_tunnels)
		if(get_dist(candidate, other_tunnel) < tunnel_minimum_spacing)
			return FALSE
	return TRUE

/obj/effect/landmark/procedural_frontier_generator/proc/place_platinum_landmarks(list/open_cave_tiles)
	var/list/mineral_candidates = open_cave_tiles.Copy()
	for(var/i in 1 to min(miner_platinum_count, length(mineral_candidates)))
		new /obj/effect/landmark/miner_platinum(pick_n_take(mineral_candidates))

/obj/effect/landmark/procedural_frontier_generator/proc/place_xenomorph_spawns(list/open_cave_tiles)
	if(!length(open_cave_tiles))
		return
	// Spread deterministic job spawns through the collected cave-tile list.
	for(var/spawn_index in 1 to xenomorph_spawn_count)
		var/list_index = round(1 + (length(open_cave_tiles) - 1) * (spawn_index - 1) / max(1, xenomorph_spawn_count - 1))
		new /obj/effect/landmark/start/job/xenomorph(open_cave_tiles[list_index])

/obj/effect/landmark/procedural_frontier_generator/proc/place_excavation_sites(list/open_cave_tiles, datum/procedural_frontier_layout/layout)
	var/list/site_candidates = list()
	for(var/turf/candidate in open_cave_tiles)
		if(get_dist(candidate, layout.get_landing_center()) > landing_surface_radius)
			site_candidates += candidate
	for(var/i in 1 to min(excavation_site_count, length(site_candidates)))
		var/turf/site_turf = pick_n_take(site_candidates)
		if(site_turf)
			new /obj/effect/landmark/excavation_site_spawner(site_turf)
