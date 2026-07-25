extends CharacterBody3D
class_name TheChild

const SPEED: float = 2.5
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const CAM_ROT_SPEED_MOUSE: float = 0.0025
const CAM_ROT_SPEED_JOYPD: float = 0.0025
const DAMPING_FACTOR: float = 0.93
const SPRING_STRENGTH: float = 100.0
enum DeviceID {KYBRD, MSBTN, JYBTN, JYAXS}

@onready var Camera: Camera3D = $Camera3D
@onready var Area: Area3D = $Area3D
@onready var Flashlight: SpotLight3D = $SpotLight3D
@onready var FlashlightArea: Area3D = $SpotLight3D/Area3D

var allow_inputs := false
var allow_movement := false
var flashlight_velocity := Vector2.ZERO
var NearbyThings: Array[Interactable]

# ╭----------------╮
# |    UTILITY     |
# ╰----------------╯
func _ready():
   Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
   var register_input: Callable = func(input_name: String, device_id: DeviceID, button: int):
      if not InputMap.has_action(input_name): InputMap.add_action(input_name)
      var event
      if   device_id == DeviceID.KYBRD: event = InputEventKey.new();          event.keycode = button  
      elif device_id == DeviceID.MSBTN: event = InputEventMouseButton.new();  event.button_index = button
      elif device_id == DeviceID.JYBTN: event = InputEventJoypadButton.new(); event.button_index = button
      elif device_id == DeviceID.JYAXS: event = InputEventJoypadMotion.new(); event.axis = button
      else: print("DEVICE NOT VALID"); return
      InputMap.action_add_event(input_name, event)
   register_input.call("jump",          DeviceID.KYBRD, Key.KEY_SPACE)
   register_input.call("jump",          DeviceID.JYBTN, JoyButton.JOY_BUTTON_A)
   register_input.call("left",          DeviceID.KYBRD, Key.KEY_A)
   register_input.call("down",          DeviceID.KYBRD, Key.KEY_S)
   register_input.call("right",         DeviceID.KYBRD, Key.KEY_D)
   register_input.call("up",            DeviceID.KYBRD, Key.KEY_W)
   register_input.call("interact",      DeviceID.KYBRD, Key.KEY_E)
   register_input.call("interact",      DeviceID.MSBTN, MouseButton.MOUSE_BUTTON_LEFT)
   register_input.call("interact",      DeviceID.JYBTN, JoyButton.JOY_BUTTON_X)
   register_input.call("flashlight",    DeviceID.KYBRD, Key.KEY_Q)
   register_input.call("flashlight",    DeviceID.MSBTN, MouseButton.MOUSE_BUTTON_RIGHT)
   register_input.call("flashlight",    DeviceID.JYBTN, JoyButton.JOY_BUTTON_Y)
   register_input.call("capture_mouse", DeviceID.KYBRD, Key.KEY_ESCAPE)
   register_input.call("capture_mouse", DeviceID.JYBTN, JoyButton.JOY_BUTTON_START)
   
   Area.body_entered.connect(_on_body_entered)
   Area.body_exited.connect(_on_body_exited)
   FlashlightArea.body_entered.connect(_on_body_entered_flashlight)
   FlashlightArea.body_exited.connect(_on_body_exited_flashlight)

func _on_body_entered(body: Node3D) -> void:
   var parent := body.get_parent()
   if parent and parent is Interactable and not NearbyThings.has(parent):
      NearbyThings.append(parent)

func _on_body_exited(body: Node3D) -> void:
   var parent := body.get_parent()
   if parent and parent is Interactable:
      NearbyThings.erase(parent)
    
func _on_body_entered_flashlight(body: Node3D) -> void:
   if body is TheCreature:
      print("CREATURE SPOTTED")
      
func _on_body_exited_flashlight(body: Node3D) -> void:
   if body is TheCreature:
      print("CREATURE OUT OF SIGHT")


# mouse
func _unhandled_input(event):
   if event is InputEventMouseMotion and allow_inputs:
      rotate_y(-event.relative.x * CAM_ROT_SPEED_MOUSE)
      Flashlight.rotate_y(event.relative.x * CAM_ROT_SPEED_MOUSE)
      Camera.rotate_x(-event.relative.y * CAM_ROT_SPEED_MOUSE)
      Camera.rotation.x = clamp(Camera.rotation.x, -PI/2, PI/2)

func _process(delta):
   ## CAPTURE AND FREE CAMERA ON ESC
   if Input.is_action_just_pressed("capture_mouse"):# or \
   #Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not mouse_captured:
      allow_inputs = ! allow_inputs
      if allow_inputs: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
      else:Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
   
   ## HANDLE JOYSTICK CAMERA MOVEMENT
   #var joystick_camera_input = Input.get_vector("camera_joystick_left", "camera_joystick_right", "camera_joystick_up", "camera_joystick_down")
   #joystick_camera_input *= Vector2(statistics.joystick_camera_sensitivity_x,statistics.joystick_camera_sensitivity_y)
   #if accept_inputs and joystick_camera_input != Vector2.ZERO:
   #	if !Global.joystick_camera_lock or Global.first_person_camera:
   #		player.rotate_y(-joystick_camera_input.x * get_physics_process_delta_time())
   #		head.rotate_x(-joystick_camera_input.y * get_physics_process_delta_time())
   #		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)
   print(NearbyThings)
   if Input.is_action_just_pressed("interact") and allow_inputs:
      for thing:Interactable in NearbyThings:
         thing.on_interact()
   if Input.is_action_just_pressed("flashlight") and allow_inputs:
      Flashlight.visible = not Flashlight.visible
   
   var diff := Vector2(
      Camera.rotation.x - Flashlight.rotation.x,
      0 - Flashlight.rotation.y
   )
   var acceleration: Vector2 = diff * SPRING_STRENGTH
   flashlight_velocity += acceleration*delta
   flashlight_velocity *= DAMPING_FACTOR
   
   Flashlight.rotation.x += flashlight_velocity.x * delta
   Flashlight.rotation.y += flashlight_velocity.y * delta
   #
   #if abs(diff.length()) < 0.03 and abs(flashlight_velocity.length()) < 0.03 and abs(flashlight_velocity.length()) > 0:
      #Flashlight.rotation.x = Camera.rotation.x
      #Flashlight.rotation.y = 0 
      #flashlight_velocity = Vector2.ZERO
   
   

# movement
func _physics_process(delta):
   if not allow_inputs: return
   if not is_on_floor(): velocity.y -= GRAVITY * delta
   
   ## NO JUMP
   #if Input.is_action_just_pressed("jump") and is_on_floor(): velocity.y = JUMP_VELOCITY
   
   if not allow_movement: return
   
   var input_dir = Input.get_vector("left", "right", "up", "down")
   var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
   if direction:
      velocity.x = direction.x * SPEED
      velocity.z = direction.z * SPEED
   else:
      velocity.x = move_toward(velocity.x, 0, SPEED)
      velocity.z = move_toward(velocity.z, 0, SPEED)

   move_and_slide()

func is_at_door() -> bool:
   var is_at_door = false
   if self.global_position.distance_to(self.get_parent().global_position) < 1.0: is_at_door = true
   return is_at_door
