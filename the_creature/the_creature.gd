extends CharacterBody3D
class_name TheCreature

@export var movement_speed: float = 1.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var Area: Area3D = $Area3D
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var knowledge : InfoPacket
var current_target : Node3D
var angle_to_target : float
var NearbyThings: Array[Interactable]
#var eagerness : float

func _ready() -> void:
   navigation_agent.velocity_computed.connect(Callable(_on_velocity_computed))
   Area.body_entered.connect(_on_area_entered)
   Area.body_exited.connect(_on_area_exited)

func _process(delta: float) -> void:
   if current_target == null: print("no target")
   else: print(current_target.global_position)
   
   ## TURN OFF LAMP IF WITHIN RANGE
   if current_target is Light and NearbyThings.has(current_target):
      if current_target.Powered == false: current_target.on_interact()
      current_target = null
   
   ## CHOOSE TARGET
   if current_target == null:
      if not knowledge.lit_lamp_list.is_empty():
         var choice = randi_range(0, knowledge.lit_lamp_list.size()-1)
         current_target = knowledge.lit_lamp_list[choice]
         set_movement_target(current_target.global_position)

func recieve_information(packet : InfoPacket) -> void:
   knowledge = packet

func set_movement_target(movement_target: Vector3):
   navigation_agent.set_target_position(movement_target)

func _physics_process(delta: float):
   # Do not query when the map has never synchronized and is empty.
   if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
      return
   if navigation_agent.is_navigation_finished():
      return

   var next_path_position: Vector3 = navigation_agent.get_next_path_position()
   var new_velocity: Vector3 = global_position.direction_to(next_path_position) * movement_speed
   if navigation_agent.avoidance_enabled:
      navigation_agent.set_velocity(new_velocity)
   else:
      _on_velocity_computed(new_velocity, delta)
   
   var target_vector = global_position.direction_to(navigation_agent.get_next_path_position())
   var target_basis= Basis.looking_at(target_vector)
   basis = basis.slerp(target_basis, 0.5)

func _on_velocity_computed(safe_velocity: Vector3, _delta:float):
   velocity = safe_velocity
   #if not is_on_floor(): velocity.y -= gravity * delta
   move_and_slide()

func _on_area_entered(body: Node3D) -> void:
   var parent := body.get_parent()
   if parent and parent is Interactable:
      NearbyThings.append(parent)

func _on_area_exited(body: Node3D) -> void:
   var parent := body.get_parent()
   if parent and parent is Interactable:
      NearbyThings.erase(parent)
