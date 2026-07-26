extends Node3D

@onready var MAIN_SCENE = preload("res://the_home/the_home.tscn")

func _ready() -> void:
   var game_attempt = MAIN_SCENE.instantiate()
   add_child(game_attempt)

func reset_game():
   for i in get_children():
      i.queue_free()
   var game_attempt = MAIN_SCENE.instantiate()
   add_child(game_attempt)
   game_attempt.skip_tutorial_for_game_reset()
