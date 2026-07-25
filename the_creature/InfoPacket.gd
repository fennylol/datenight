extends Node
class_name InfoPacket

var child_location : Vector3
var lit_lamp_locations : Array[Vector3]

func _init(c_loc: Vector3 = Vector3.ZERO, l_loc: Array[Vector3] = []) -> void:
   child_location = c_loc
   lit_lamp_locations = l_loc
