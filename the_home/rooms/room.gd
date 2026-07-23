extends Node3D
class_name Room

var Doors: Array[Door]
var BoundingBox: AABB 
@export var RoomName: String

func _ready() -> void:
   BoundingBox = GlobalUtil.calculate_spatial_bounds(self, false)
