extends CharacterBody3D
class_name TheDetourCreature

@export var movement_speed: float = 10.0
@export var evade_speed: float = 5.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var Area: Area3D = $Area3D
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var knowledge : InfoPacket
var current_target : Node3D
var angle_to_target : float
var NearbyThings: Array[Interactable]
#var eagerness : float

enum MovementStates {NORMAL, EVADING, PINNED}
var MovementState := MovementStates.NORMAL
var OldTarget := Vector3.ZERO

@export var Benevolent: bool = false

## ---- GAZE AVOIDANCE ----
## The conical Area3D on the player. Assign in the inspector, or leave empty
## and put the cone in a group called "gaze_cone".
@export var gaze_cone: Area3D
## Roughly how far the cone reaches. Detour waypoints sit on a ring this far
## from the player, plus padding.
@export var cone_reach: float = 10.0
@export var ring_padding: float = 2.0
@export var ring_samples: int = 12
## Distance between point tests along a path segment. Keep well under the
## cone's narrowest width or a thin cone slips between samples.
@export var sample_step: float = 0.5
@export var replan_interval: float = 0.25
## How long the creature must be clear of the cone before it stops evading.
## This is the hysteresis -- without it, it jitters on the cone boundary.
@export var evade_clear_time: float = 0.3
## PINNED fallback (no legal detour/escape at all): concentric rings to
## search for a point outside the player's line of sight, checked cheaply
## (endpoint visibility only, not the full cone-shape + path-leg search).
## Needs to reach past `cone_reach + ring_padding`, since PINNED is only
## entered after that ring already failed -- a long hallway can put the
## entire corridor, well past the normal ring, inside the cone.
@export var pinned_search_radii: PackedFloat32Array = PackedFloat32Array([12.0, 20.0, 32.0])
## What a line-of-sight ray from the player must hit to count as "wall".
## Defaults to the everything-is-layer-1 convention this project already
## uses elsewhere (see `_point_query.collision_mask` below).
@export var line_of_sight_mask: int = 1

var final_goal := Vector3.ZERO
var detour_point := Vector3.ZERO
var has_detour := false

var _replan_timer := 0.0
var _clear_time := 0.0
var _last_cone_pos := Vector3.ZERO
var _last_cone_yaw := 0.0
var _point_query := PhysicsPointQueryParameters3D.new()
var _los_exclude: Array[RID] = []


func _ready() -> void:
   navigation_agent.velocity_computed.connect(_on_velocity_computed)
   Area.body_entered.connect(func(body: Node3D): var parent := body.get_parent(); if parent and parent is Interactable: NearbyThings.append(parent))
   Area.body_exited.connect (func(body: Node3D): var parent := body.get_parent(); if parent and parent is Interactable: NearbyThings.erase(parent))

   if gaze_cone == null:
      gaze_cone = get_tree().get_first_node_in_group("gaze_cone") as Area3D
   if gaze_cone == null:
      push_warning("TheCreature: no gaze_cone assigned, gaze avoidance is off.")
   else:
      _point_query.collide_with_areas = true
      _point_query.collide_with_bodies = false
      _point_query.collision_mask = gaze_cone.collision_layer
      _last_cone_pos = gaze_cone.global_position
      _last_cone_yaw = gaze_cone.global_rotation.y

      ## Exclude the player's own body and ours from LOS rays -- both sit
      ## right at the ray's endpoints and would otherwise self-block.
      _los_exclude = [get_rid()]
      var player_body := gaze_cone.owner as CollisionObject3D
      if player_body:
         _los_exclude.append(player_body.get_rid())


func recieve_information(packet : InfoPacket) -> void: knowledge = packet
func set_movement_target(movement_target: Vector3): navigation_agent.set_target_position(movement_target)

func _process(_delta: float) -> void:
   ## TURN OFF LAMP IF WITHIN RANGE
   if current_target is Light and NearbyThings.has(current_target):
      if current_target.Powered == true or Benevolent: current_target.on_interact()
      current_target = null

   ## CHOOSE TARGET
   if current_target == null: select_new_target()

func select_new_target() -> void:
   match MovementState:
      MovementStates.NORMAL:
         if knowledge == null: return
         current_target = knowledge.lamp_list.pick_random() if knowledge.lit_lamp_list.is_empty() or Benevolent else knowledge.lit_lamp_list.pick_random()
         if current_target == null: return
         final_goal = current_target.global_position
         has_detour = false
         _replan()
      MovementStates.EVADING, MovementStates.PINNED:
         pass


func _physics_process(delta: float):
   # Do not query when the map has never synchronized and is empty.
   if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0: return

   ## GAZE LOGIC -- runs before the is_navigation_finished check, because
   ## arriving at a detour waypoint is exactly when we need to re-plan.
   _update_gaze(delta)

   if navigation_agent.is_navigation_finished():
      if has_detour:
         ## Reached the intermediate waypoint. Resume the real goal next tick.
         has_detour = false
         _replan_timer = 0.0
      return

   var speed := movement_speed if MovementState == MovementStates.NORMAL else evade_speed

   var next_path_position: Vector3 = navigation_agent.get_next_path_position()
   var new_velocity: Vector3 = global_position.direction_to(next_path_position) * speed
   if navigation_agent.avoidance_enabled:
      navigation_agent.set_velocity(new_velocity)
   else: _on_velocity_computed(new_velocity)

   var target_vector = global_position.direction_to(navigation_agent.get_next_path_position())
   if target_vector.length_squared() > 0.001:
      var target_basis= Basis.looking_at(target_vector)
      basis = basis.slerp(target_basis, movement_speed * delta * 2).orthonormalized()

func _on_velocity_computed(safe_velocity: Vector3):
   velocity = safe_velocity
   move_and_slide()


## ------------------------------------------------------------------
##  GAZE AVOIDANCE
## ------------------------------------------------------------------

func _update_gaze(delta: float) -> void:
   if gaze_cone == null: return
   var inside: bool = gaze_cone.overlaps_body(self) and _has_line_of_sight(global_position)

   match MovementState:
      MovementStates.NORMAL:
         if inside:
            _enter_evading()
            return
         _replan_timer -= delta
         if _replan_timer <= 0.0:
            _replan_timer = replan_interval
            if _cone_moved_enough():
               _replan()

      MovementStates.EVADING:
         if inside:
            _clear_time = 0.0
            ## Escape point turned out to be inside too -- pick another.
            if navigation_agent.is_navigation_finished():
               _pick_escape_point()
         else:
            _clear_time += delta
            if _clear_time >= evade_clear_time:
               _resume_normal()

      MovementStates.PINNED:
         if inside:
            _clear_time = 0.0
            ## Still haven't outrun it -- pick a fresh flee point, not a
            ## full ring search. PINNED stays cheap by design.
            if navigation_agent.is_navigation_finished():
               _flee()
         else:
            _clear_time += delta
            if _clear_time >= evade_clear_time:
               _resume_normal()


func _enter_evading() -> void:
   MovementState = MovementStates.EVADING
   OldTarget = final_goal
   has_detour = false
   _clear_time = 0.0
   _pick_escape_point()


## Last resort when NORMAL's ring search or EVADING's escape search both
## come up empty -- fully boxed in. Skip cone testing and the ring/path
## queries entirely and hunt for a spot the player can't see instead; it's
## the cheap analog to the real detour search, meant for a case that
## should be rare and transient.
func _enter_pinned() -> void:
   MovementState = MovementStates.PINNED
   OldTarget = final_goal
   has_detour = false
   _clear_time = 0.0
   _flee()


func _flee() -> void:
   var map := navigation_agent.get_navigation_map()

   var hidden := _find_pinned_escape(map)
   if hidden != Vector3.INF:
      set_movement_target(hidden)
      return

   ## Nowhere searched is hidden -- a strict dead end has no point to hide
   ## behind at all, and heading for `final_goal` isn't reliable here either
   ## (it may already be behind the player, may equal where we're
   ## standing, or may just not be what pulls the agent out of the pocket).
   ## Target the player directly instead: it's guaranteed to be on the only
   ## path out of the dead end, so it's the one target that's certain to
   ## get the navigation agent moving rather than sitting idle.
   set_movement_target(gaze_cone.global_position)


## Concentric rings around the player. Every sample on a given ring is
## (roughly) equally far from the player, so the ring itself is the
## "furthest from player" tier; the winner within it is whichever sample is
## closest to us. A farther ring with any hidden point always beats a
## nearer one, matching the requested preference order -- independent of
## what order `pinned_search_radii` happens to be listed in.
func _find_pinned_escape(map: RID) -> Vector3:
   var origin := gaze_cone.global_position
   var best := Vector3.INF
   var best_radius := -1.0

   for radius in pinned_search_radii:
      if radius <= best_radius: continue

      var band_best := Vector3.INF
      var band_best_self_dist := INF
      for i in ring_samples:
         var ang := TAU * float(i) / float(ring_samples)
         var p := origin + Vector3(cos(ang), 0.0, sin(ang)) * radius
         p = NavigationServer3D.map_get_closest_point(map, p)
         if _has_line_of_sight(p): continue

         var self_dist := global_position.distance_to(p)
         if self_dist < band_best_self_dist:
            band_best = p
            band_best_self_dist = self_dist

      if band_best != Vector3.INF:
         best = band_best
         best_radius = radius

   return best


func _resume_normal() -> void:
   MovementState = MovementStates.NORMAL
   _replan_timer = 0.0
   if current_target != null:
      final_goal = current_target.global_position
   elif OldTarget != Vector3.ZERO:
      final_goal = OldTarget
   _replan()


## Sidestep beats backing out -- retreating through the apex walks at the
## player. Try both sides, then straight out, at increasing distances.
func _pick_escape_point() -> void:
   var map := navigation_agent.get_navigation_map()
   var v := global_position - gaze_cone.global_position
   v.y = 0.0
   var radial := v.normalized() if v.length_squared() > 0.001 else Vector3.FORWARD
   var side := radial.cross(Vector3.UP).normalized()

   for dir in [side, -side, radial]:
      for dist in [2.0, 4.0, 7.0]:
         var p := NavigationServer3D.map_get_closest_point(map, global_position + dir * dist)
         if not _in_cone(p):
            set_movement_target(p)
            return

   ## Boxed in on every side -- stop the expensive search and just run.
   _enter_pinned()


func _replan() -> void:
   if gaze_cone == null:
      set_movement_target(final_goal)
      return

   var map := navigation_agent.get_navigation_map()

   ## Direct route clear? Drop whatever detour we were holding.
   if not _path_hits_cone(NavigationServer3D.map_get_path(map, global_position, final_goal, true)):
      has_detour = false
      set_movement_target(final_goal)
      return

   ## Still-valid detour is cheaper than resampling the ring.
   if has_detour:
      if not _path_hits_cone(NavigationServer3D.map_get_path(map, global_position, detour_point, true)):
         set_movement_target(detour_point)
         return

   var found := _find_detour(map)
   if found == Vector3.INF:
      ## No legal detour exists -- stop searching and run.
      _enter_pinned()
      return

   detour_point = found
   has_detour = true
   set_movement_target(detour_point)


## Ring of candidates around the player, snapped to the navmesh, sorted by
## total detour length. First one whose BOTH legs stay clear wins.
func _find_detour(map: RID) -> Vector3:
   var origin := gaze_cone.global_position
   var radius := cone_reach + ring_padding

   var candidates: Array = []
   for i in ring_samples:
      var ang := TAU * float(i) / float(ring_samples)
      var p := origin + Vector3(cos(ang), 0.0, sin(ang)) * radius
      p = NavigationServer3D.map_get_closest_point(map, p)
      if _in_cone(p): continue
      candidates.append([global_position.distance_to(p) + p.distance_to(final_goal), p])

   candidates.sort_custom(func(a, b): return a[0] < b[0])

   for c in candidates:
      var cand: Vector3 = c[1]
      if _path_hits_cone(NavigationServer3D.map_get_path(map, global_position, cand, true)): continue
      if _path_hits_cone(NavigationServer3D.map_get_path(map, cand, final_goal, true)): continue
      return cand

   return Vector3.INF


## Tests a world point against the actual Area3D shape -- no cone maths, and
## the vertical extent comes along for free. Geometrically inside is not
## enough: a point behind a wall isn't actually seen, so it doesn't count.
func _in_cone(p: Vector3) -> bool:
   _point_query.position = p
   for hit in get_world_3d().direct_space_state.intersect_point(_point_query, 8):
      if hit.collider == gaze_cone:
         return _has_line_of_sight(p)
   return false


## Casts from the player toward `to` and checks whether anything solid --
## a wall -- gets in the way first. Areas (the cone itself included) don't
## block; only physics bodies do.
func _has_line_of_sight(to: Vector3) -> bool:
   var query := PhysicsRayQueryParameters3D.create(gaze_cone.global_position, to, line_of_sight_mask, _los_exclude)
   query.collide_with_areas = false
   query.collide_with_bodies = true
   return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Path points alone are not enough: navmesh paths have long straight runs and
## the cone will sit happily in the middle of one. Sample along each segment.
func _path_hits_cone(path: PackedVector3Array) -> bool:
   if path.size() < 2: return false
   for i in path.size() - 1:
      var a := path[i]
      var b := path[i + 1]
      var steps := maxi(int(a.distance_to(b) / sample_step), 1)
      for s in steps + 1:
         if _in_cone(a.lerp(b, float(s) / float(steps))):
            return true
   return false


## A stationary player costs nothing.
func _cone_moved_enough() -> bool:
   var yaw := gaze_cone.global_rotation.y
   var turned := absf(wrapf(yaw - _last_cone_yaw, -PI, PI)) > deg_to_rad(4.0)
   var walked := gaze_cone.global_position.distance_to(_last_cone_pos) > 0.75
   if turned or walked:
      _last_cone_yaw = yaw
      _last_cone_pos = gaze_cone.global_position
      return true
   return false
