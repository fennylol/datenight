extends Interactable
class_name Light

var Powered: bool = true
var Power: float = 0.0

@onready var Bulb: Light3D = $Bulb

func _ready() -> void:
   Power = Bulb.light_energy

func on_interact() -> void:
   Powered = not Powered
   Bulb.light_energy = Power if Powered else 0.0
