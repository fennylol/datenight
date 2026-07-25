extends Node3D
class_name Room

@export var RoomName: String
@export var Doors   : Array[Door]
@export var Lights  : Array[Light]

const MAX_SEARCH : int = 3
var BoundingBox: AABB 


func _ready() -> void:
   BoundingBox = GlobalUtil.calculate_spatial_bounds(self, false)

func _find_lights():
   for i in get_children():
      pass
