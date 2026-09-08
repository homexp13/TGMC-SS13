# Procedural Frontier

`procedural_frontier` is a 199×199 all-cave ground map. Its authored `.dmm`
is only a 199×199 turf shell and a generator landmark; the map contents are
created when the round starts.

There is no city generation. Every non-boundary tile belongs to the cave
generator. A 30×40 landing zone is placed at a random valid location each
round and receives clear plating. It has a carved exit into the cave network.
The map boundary is indestructible Big Red rock.

The LZ has a reinforced perimeter, two three-tile southern exits, LZ1 docking
port, a complete outer ring of containment poddoors, landing floodlights, an
APC, a landing-zone button, a hangar stencil, and folding barricades just inside
the exits. The 11×21 dropship footprint is entirely clean plating; the rest of
the LZ uses asteroid floor.

The configurable variables on
`/obj/effect/landmark/procedural_frontier_generator` are:

* `map_width` / `map_height` — currently 199 each. These must agree with the
  authored `.dmm` size.
* `landing_width` / `landing_height` — currently 30×40.
* `pad_width` / `pad_height` — the docking pad remains 11×21, matching the
  marine dropship's stationary LZ1 port.
* `landing_edge_margin` — minimum distance between the pad and map edge.
* `landing_edge_opening` — exponential gradient rate (currently `4.0`).
* `landing_surface_radius` — open terrain radius around the LZ (currently 24).
* `cave_ridge_threshold` — base ridge-noise cutoff.
* `central_landing_complexity` — extra cutoff for a central pad; it fades out
  toward map edges, so edge pads produce more open caves.
* `excavation_site_count` — number of randomly distributed excavation sites.
* `hard_ridge_cutoff` / `deep_wall_separation` / `deep_cave_wall_type` — the
  hard ridge test selects candidate solid tiles, then only tiles separated
  from open cave by the configured radius become deep-rock (`r_wall` for
  testing). This is independent of LZ distance.
* `noise_coarse_scale` / `noise_fine_scale` / `noise_coarse_weight` — the two
  value-noise layers and their blend.
* `weed_node_spacing`, `tunnel_edge_offset`, `tunnel_minimum_spacing`,
  `miner_platinum_count`, and `xenomorph_spawn_count` — landmark placement.

`procedural_frontier_landing_threshold()` is the dedicated normalized
exponential gradient function: it returns `0` at the landing zone and rises
quickly before asymptotically slowing toward `1` at the farthest edge. The
generator first reserves an open surface ring around the landing, then raises
the ridge cutoff with distance. As a result, the LZ surroundings are open
terrain, while the remote map contains more frequent, narrow cave passages.

Weed nodes use a five-tile lattice on open cave floor. Xeno tunnels are placed
near separate map corners, platinum landmarks are distributed in caves, and
xenomorph start landmarks remain on ground cave tiles only.

The implementation is split into `create_layout`, `generate_terrain`,
`carve_landing_exit`, `retain_reachable_cave_tiles`, and landmark-placement
procs. The reachability stage flood-fills from the LZ and seals every isolated
open pocket before placing landmarks, so unreachable cave chunks cannot get
tunnels or spawns.
The shared `procedural_frontier_layout` datum contains all derived coordinates
for one run, so additional biomes or structures can consume the same map
geometry without duplicating boundary and landing calculations.
