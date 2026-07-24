extends Node3D

@onready var THE_CHILD: TheChild = $TheChild
@onready var THE_CREATURE: TheCreature = $TheCreature
@onready var ROOMS: Node3D = $NavigationRegion3D/Rooms

var last_room: Room

func _get_containing_room() -> Room:
   for room:Room in ROOMS.get_children():
      if room.BoundingBox.has_point(THE_CHILD.position):
         return room
   return null

func _process(_delta: float) -> void:
   THE_CREATURE.set_movement_target(THE_CHILD.position)
   
   var closest_room: Room = _get_containing_room()
   if closest_room != last_room:
      print(closest_room.RoomName if closest_room else "idk where you are LMAO")
      last_room = closest_room
