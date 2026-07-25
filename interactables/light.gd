extends Interactable
class_name Light

@export var Powered: bool = false
var Power: float = 0.0

@onready var Bulb: Light3D = $Bulb

func _ready() -> void:
   Power = Bulb.light_energy
   if not Powered:
      Bulb.visible = Powered
      Bulb.light_energy = Power if Powered else 0.0

func on_interact() -> void:
   Powered = not Powered
   Bulb.visible = Powered
   Bulb.light_energy = Power if Powered else 0.0
