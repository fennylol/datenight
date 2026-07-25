extends CharacterBody3D
class_name TheCreature

@export var movement_speed: float = 1.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_target := Vector3.ZERO
var angle_to_target : float

func _ready() -> void:
   navigation_agent.velocity_computed.connect(Callable(_on_velocity_computed))

func recieve_information(packet : InfoPacket) -> void:
   #if current_target != Vector3.ZERO: set_movement_target(current_target)
   #print(packet.lit_lamp_locations)
   if packet.lit_lamp_locations.is_empty():
      set_movement_target(packet.child_location)
   #else:
   #   var choice = randi_range(0,packet.lit_lamp_locations.size()-1)
   #   set_movement_target(packet.lit_lamp_locations[choice])

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
