extends Node3D
class_name Room

@export var RoomName: String
@export var Doors   : Array[Door]
@export var Lights  : Array[Light]

var BoundingBox: AABB 


func _ready() -> void:
   BoundingBox = GlobalUtil.calculate_spatial_bounds(self, false)
