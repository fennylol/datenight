extends CharacterBody3D
class_name TheCreature

var HUNT_SPEED: float = 3
var NORMAL_SPEED: float = 10
var FLEE_SPEED: float = 15

@export var movement_speed: float = 10.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var Area: Area3D = $Area3D
@onready var AnimPlayer = $goose/AnimationPlayer
@onready var MaskPivot = $goose/MaskPivot
@onready var Sounds: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var HuntSounds: AudioStreamPlayer3D = $Hunt
@onready var KillSounds: AudioStreamPlayer3D = $Kill
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var knowledge : InfoPacket
var current_target : Node3D
var angle_to_target : float
var NearbyThings: Array[Interactable]
var Anger: float = 0.0
var FleeTimer: float = 0.0
var FLEE_TIME: float = 2.5

enum MovementStates {NORMAL, FLEEING, HUNTING}
var MovementState := MovementStates.NORMAL:
   set(new_state):
      MovementState = new_state
      if new_state == MovementStates.HUNTING:
         HuntSounds.stream = load("res://the_creature/sounds/hunt_0.mp3") if randf() > 0.5 else load("res://the_creature/sounds/hunt_1.mp3")
         HuntSounds.play()
var OldTarget := Vector3.ZERO

@export var Benevolent: bool = false

func _ready() -> void:
   navigation_agent.velocity_computed.connect(_on_velocity_computed)
   Area.body_entered.connect(func(body: Node3D): var parent := body.get_parent(); if parent and parent is Interactable: NearbyThings.append(parent))
   Area.body_exited.connect (func(body: Node3D): var parent := body.get_parent(); if parent and parent is Interactable: NearbyThings.erase(parent))
   AnimPlayer.play("walk_cycle/walk")
   AnimPlayer.current_animation = "walk_cycle/walk"
   Sounds.finished.connect(Sounds.play)

func recieve_information(packet : InfoPacket) -> void: knowledge = packet
func set_movement_target(movement_target: Vector3): navigation_agent.set_target_position(movement_target)

func _process(delta: float) -> void:
   if MovementState == MovementStates.FLEEING:
      FleeTimer -= delta
      if FleeTimer < 0:
         MovementState = MovementStates.NORMAL
   
   match MovementState:
      MovementStates.NORMAL: movement_speed = NORMAL_SPEED
      MovementStates.FLEEING: movement_speed = FLEE_SPEED
      MovementStates.HUNTING: movement_speed = HUNT_SPEED
   
   ## TURN OFF LAMP IF WITHIN RANGE
   if current_target is Light and NearbyThings.has(current_target):
      if current_target.Powered == true or Benevolent: current_target.on_interact()
      current_target = null
      Anger = 0
   
   ## CHOOSE TARGET
   if current_target == null: 
      ## determine agression based on time and lamps lit
      var time_aggression = ( floor( ( knowledge.game_time / get_parent().SECONDS_TO_GAME_HOUR ) * 4 ) / 4 )
      var light_aggression = knowledge.lamp_list.size() - knowledge.lit_lamp_list.size()
      var total_aggression = float( time_aggression * light_aggression ) / 60.0
      var roll_for_attack = randf()
      if roll_for_attack < total_aggression: MovementState = MovementStates.HUNTING
      select_new_target()

func spotted() -> void:
   if MovementState == MovementStates.FLEEING or MovementState == MovementStates.HUNTING: return
   MovementState = MovementStates.FLEEING
   FleeTimer = FLEE_TIME
   Anger += 1
   if Anger >= 2: 
      MovementState = MovementStates.HUNTING
      print("HUNTING with anger: ", Anger)
   else:
      print("FLEEING with anger: ", Anger)
   select_new_target()
   
 
func select_new_target() -> void:
   match MovementState:
      MovementStates.NORMAL:
         var random_lamp: Light = null
         var temp_lamp_list: Array[Light] = knowledge.lamp_list.duplicate_deep()
         ## attempt to find a lit lamp if needed
         if not (knowledge.lit_lamp_list.is_empty() or Benevolent):
            var temp_lit_list: Array[Light] = knowledge.lit_lamp_list.duplicate_deep()
            while random_lamp == null and temp_lit_list.size() >= 1:
               random_lamp = temp_lit_list.pop_at(randi_range(0, temp_lit_list.size()-1))
               if random_lamp.global_position.distance_to(knowledge.child.global_position) < 5:
                  random_lamp = null

         while random_lamp == null and temp_lamp_list.size() >= 1:
            random_lamp = temp_lamp_list.pop_at(randi_range(0, temp_lamp_list.size()-1))
            if random_lamp.global_position.distance_to(knowledge.child.global_position) < 5:
               random_lamp = null

         current_target = random_lamp
      
      MovementStates.FLEEING:
         var random_lamp: Light = null
         var temp_lamp_list: Array[Light] = knowledge.lamp_list.duplicate_deep()
         while random_lamp == null and temp_lamp_list.size() >= 1:
            random_lamp = temp_lamp_list.pop_at(randi_range(0, temp_lamp_list.size()-1))
            if random_lamp.position.distance_to(knowledge.child.position) < 10:
               random_lamp = null
         current_target = random_lamp
      
      MovementStates.HUNTING:
         current_target = knowledge.child
         
   if current_target: set_movement_target(current_target.global_position)


func _physics_process(delta: float):
   # Do not query when the map has never synchronized and is empty.
   if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0: return
   if navigation_agent.is_navigation_finished(): return

   if MovementState == MovementStates.HUNTING: select_new_target()

   var next_path_position: Vector3 = navigation_agent.get_next_path_position()
   if MovementState == MovementStates.HUNTING: print(navigation_agent.get_path_length())
   if MovementState == MovementStates.HUNTING and navigation_agent.get_path_length() < 7:
      if not KillSounds.playing: 
         var rand: int = randi_range(0, 2)
         KillSounds.stream = load("res://the_creature/sounds/kill_" + str(rand) + ".mp3")
         KillSounds.play()
      if position.distance_to(knowledge.child.position) < 3:
         var safe: bool = false
         for thing in knowledge.child.SafetyThings:
            if thing is Light and knowledge.lit_lamp_list.has(thing):
               MovementState = MovementStates.FLEEING
               select_new_target()
               KillSounds.stop()
               KillSounds.stream = load("res://the_creature/sounds/kill_abandon.mp3")
               KillSounds.play()
               safe = true
         if not safe and position.distance_to(knowledge.child.position) < 1:
            var grand_daddy = get_parent().get_parent()
            if grand_daddy and grand_daddy is DateNight: grand_daddy.reset_game()
   
   var new_velocity: Vector3 = global_position.direction_to(next_path_position) * movement_speed
   if navigation_agent.avoidance_enabled:
      navigation_agent.set_velocity(new_velocity)
   else: _on_velocity_computed(new_velocity)
   
   var target_vector = global_position.direction_to(next_path_position)
   var target_basis= Basis.looking_at(target_vector)
   basis = basis.slerp(target_basis, movement_speed * delta * 2).orthonormalized()

func _on_velocity_computed(safe_velocity: Vector3):
   velocity = safe_velocity
   move_and_slide()
