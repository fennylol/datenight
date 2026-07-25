extends Node3D

@onready var THE_CHILD: TheChild = $TheChild
#@onready var THE_CREATURE: TheCreature = $TheCreature
@onready var THE_CREATURE: TheDetourCreature = $DetourCritter
@onready var ROOMS: Node3D = $NavigationRegion3D/Rooms
@onready var INTERFACE: Control = $Interface
@onready var EYELIDS: Control = $Interface/WAKE_UP
@onready var HUD_TEXT: Label = $Interface/TEXT
@onready var COUNTDOWN: Label = $Interface/COUNTDOWN
@onready var WORLDPROMPTS : Node3D = $WorldPrompts

var last_room: Room
var game_time : float = 0.0
var tutorial_time : float = 0.5
var tutorial_level : int = 0
enum Tutorial {BEGIN, SLEEP, WAKEUP, LIGHTS, KEEPSAFE, TIMELEFT, SHOWCLOCK}
var gameend_level : int = 0
enum GameEnd {NONE, ARRIVED, TODOOR, WAIT, SUCCESS}
const SECONDS_TO_GAME_HOUR : float = 40.0
const HOUR_DATE_NIGHT_ENDS : float = 5.0

func _ready() -> void:
   EYELIDS.visible = true
   HUD_TEXT.visible = false
   COUNTDOWN.visible = false
   Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
   ## ADVANCE GAME TIME. FIND CURRENT HOUR. FIND COUNTDOWN. SET CLOCK.
   game_time += delta
   var current_hour = ( floor( ( game_time / SECONDS_TO_GAME_HOUR ) * 4 ) / 4 )
   var countdown_hour = str(int(floor(HOUR_DATE_NIGHT_ENDS-current_hour)))
   var countdown_minute = ":" + str(int((HOUR_DATE_NIGHT_ENDS-current_hour-floor(HOUR_DATE_NIGHT_ENDS-current_hour))*60))
   if countdown_minute == ":0": countdown_minute = ":00"
   COUNTDOWN.text = countdown_hour + countdown_minute
   
   ## TUTORIAL IF EARLY, END GAME (GOOD ENDING) IF LATE
   if tutorial_level <= Tutorial.size(): _attempt_tutorial(delta)
   if current_hour >= HOUR_DATE_NIGHT_ENDS: _attempt_game_end(delta)
   
   ## SEND INFORMATION TO CREATURE
   var packet = InfoPacket.new()
   var lights_array : Array[Light]
   var lit_lights_array : Array[Light]
   for given_room : Room in ROOMS.get_children():
      for light in given_room.Lights:
         lights_array.append(light)
         if light.Powered: lit_lights_array.append(light)
   packet.game_time = game_time
   packet.child_location = THE_CHILD.position
   packet.lamp_list = lights_array
   packet.lit_lamp_list = lit_lights_array
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

func _attempt_tutorial(delta : float):
   tutorial_time -= delta
   if Input.is_key_pressed(KEY_0): tutorial_level = Tutorial.SHOWCLOCK
   if tutorial_level == Tutorial.BEGIN:
      if tutorial_time < 0.0:
         tutorial_level += 1
   elif tutorial_level == Tutorial.SLEEP:
      HUD_TEXT.text = "WAKE UP"
      HUD_TEXT.visible = true
      if Input.is_anything_pressed():
         HUD_TEXT.visible = false
         tutorial_time = 2.1
         tutorial_level += 1
   elif tutorial_level == Tutorial.WAKEUP:
      THE_CHILD.allow_inputs = true
      ## WAKE UP ANIMATION
      var wake_speed = 0 if tutorial_time > 2.0 else 100 if tutorial_time > 1.5 else 500 if tutorial_time > 0.5 else -2700 if tutorial_time > 0.25 else 2900
      EYELIDS.get_child(0).position.y -= delta * wake_speed
      EYELIDS.get_child(1).position.y += delta * wake_speed
      if tutorial_time < 0.0: 
         EYELIDS.visible = false
         tutorial_time = 4.0
         tutorial_level += 1
   elif tutorial_level == Tutorial.LIGHTS:
      if tutorial_time > 3.0: return
      elif tutorial_time > 0.0:
         HUD_TEXT.text = "TURN ON THE LIGHTS"
         HUD_TEXT.visible = true
      else:
         HUD_TEXT.visible = false
      if Input.is_action_just_pressed("interact"):
         THE_CHILD.allow_movement = true
         HUD_TEXT.visible = false
         WORLDPROMPTS.get_child(0).visible = false
         tutorial_time = 3.0
         tutorial_level += 1
   elif tutorial_level == Tutorial.KEEPSAFE:
      HUD_TEXT.text = "THEY WILL KEEP YOU SAFE"
      if tutorial_time > 2.5: return
      elif tutorial_time > 0.0:
         HUD_TEXT.visible = true
      else:
         HUD_TEXT.visible = false
         tutorial_time = 4.0
         tutorial_level += 1
   elif tutorial_level == Tutorial.TIMELEFT:
      HUD_TEXT.text = "5:00 HOURS UNTIL PARENTS RETURN"
      if tutorial_time <= 3.0:
         HUD_TEXT.visible = true
      if tutorial_time <= 0.0:
         HUD_TEXT.visible = false
         tutorial_level += 1
   elif tutorial_level == Tutorial.SHOWCLOCK:
      game_time = 0.0
      EYELIDS.visible = false
      HUD_TEXT.visible = false
      COUNTDOWN.visible = true
      tutorial_level += 1  
   
func _attempt_game_end(delta : float):
   tutorial_time -= delta
   COUNTDOWN.text = "0:00"
   if gameend_level == GameEnd.NONE:
      tutorial_time = 3.0
      gameend_level +=1
   elif gameend_level == GameEnd.ARRIVED:
      HUD_TEXT.text = "YOUR PARENTS HAVE ARRIVED"
      if tutorial_time < 2.0:
         HUD_TEXT.visible = true
      if tutorial_time < 0.0:
         tutorial_time = 3.0
         gameend_level += 1
   elif gameend_level == GameEnd.TODOOR:
      HUD_TEXT.text = "GET TO THE FRONT DOOR"
      if tutorial_time < 0.0:
            HUD_TEXT.visible = false
            gameend_level += 1
   elif gameend_level == GameEnd.WAIT:
      EYELIDS.get_child(0).position.y = 0.0
      EYELIDS.get_child(1).position.y = 320.0
      HUD_TEXT.text = "YOU SURVIVED THE NIGHT"
      EYELIDS.visible = true
      HUD_TEXT.visible = true
      EYELIDS.modulate = Color.TRANSPARENT
      HUD_TEXT.modulate = Color.TRANSPARENT
      if THE_CHILD.is_at_door():
         tutorial_time = 0.0
         gameend_level += 1
   elif gameend_level == GameEnd.SUCCESS:
      COUNTDOWN.modulate -= Color(0,0,0,0.01)
      EYELIDS.modulate += Color(0,0,0,0.01)
      HUD_TEXT.modulate += Color(0,0,0,0.01)
  
