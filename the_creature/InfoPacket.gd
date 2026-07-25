extends Node
class_name InfoPacket

var game_time : float
var child_location : Vector3
var lamp_list : Array[Light]
var lit_lamp_list : Array[Light]

func _init(time : float = 0.0, c_loc: Vector3 = Vector3.ZERO, l_list : Array[Light] = [], l_lit: Array[Light] = []) -> void:
   game_time = time
   child_location = c_loc
   lamp_list = l_list
   lit_lamp_list = l_lit
