extends Node3D

@onready var THE_CHILD: TheChild = $TheChild
@onready var THE_CREATURE: TheCreature = $TheCreature
@onready var ROOMS: Node3D = $NavigationRegion3D/Rooms
@onready var INTERFACE: Control = $Interface
@onready var WORLDPROMPTS : Node3D = $WorldPrompts

var last_room: Room
var game_time : float = 0.0
var tutorial_level : int = 0
const MAX_TUTORIAL_LEVEL : int = 4
const SECONDS_TO_GAME_HOUR : float = 90.0
const HOUR_DATE_NIGHT_ENDS : float = 5.0

func _process(delta: float) -> void:
   ## ADVANCE GAME TIME. FIND CURRENT HOUR. 
   game_time += delta
   var current_hour = floor( game_time / SECONDS_TO_GAME_HOUR )
   ## TUTORIAL IF EARLY, END GAME (GOOD ENDING) IF LATE
   if current_hour <= 0.0: _attempt_tutorial(delta)
   if current_hour >= HOUR_DATE_NIGHT_ENDS: _game_end(true)
   
   ## SEND INFORMATION TO CREATURE
   var packet = InfoPacket.new()
   packet.child_location = THE_CHILD.position
   THE_CREATURE.recieve_information(packet)
   
   var closest_room: Room = _get_containing_room()
   if closest_room != last_room:
      print(closest_room.RoomName if closest_room else "idk where you are LMAO")
      last_room = closest_room

func _get_containing_room() -> Room:
   for room:Room in ROOMS.get_children():
      if room.BoundingBox.has_point(THE_CHILD.position):
         return room
   return null

func _attempt_tutorial(delta):
   if tutorial_level == 0:
      ## WAKE UP ANIMATION
      var wake_speed = 0 if game_time < 0.5 else 100 if game_time < 1.0 else 500 if game_time < 2.0 else -2700 if game_time < 2.25 else 2900
      var wake_up = INTERFACE.get_child(0)
      wake_up.get_child(0).position.y -= delta * wake_speed
      wake_up.get_child(1).position.y += delta * wake_speed
      if game_time > 3.0: 
         wake_up.visible = false
         tutorial_level = 1
   elif tutorial_level == 1:
      var lights = INTERFACE.get_child(1)
      if game_time < 4.0: return
      elif game_time < 7.0:
         lights.visible = true
      else:
         lights.visible = false
      if Input.is_action_just_pressed("interact") and THE_CHILD.NearbyThings.size():
         WORLDPROMPTS.get_child(0).visible = false
         game_time = 0.0
         tutorial_level = 2
   elif tutorial_level == 2:
      var lights = INTERFACE.get_child(1)
      lights.visible = true
      lights.get_child(0).text = "they will keep you safe."
      if game_time > 3.0:
         lights.visible = false
         tutorial_level = 3
   
func _game_end(good_ending: bool = false):
   pass
