extends CharacterBody3D
class_name TheChild

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@onready var camera = $Camera3D

var  mouse_captured = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# ╭----------------╮
# |    UTILITY     |
# ╰----------------╯
func register_input(input_name: String, keycode: Key):
   InputMap.add_action(input_name)
   var event = InputEventKey.new()
   event.keycode = keycode
   InputMap.action_add_event(input_name, event)


func _ready():
   register_input("jump", KEY_SPACE)
   register_input("left", KEY_A)
   register_input("down", KEY_S)
   register_input("right", KEY_D)
   register_input("up", KEY_W)
   register_input("capture_mouse", KEY_ESCAPE)

# mouse
func _unhandled_input(event):
   if event is InputEventMouseMotion and  mouse_captured:
      rotate_y(-event.relative.x * .005)
      camera.rotate_x(-event.relative.y * .005)
      camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

# mouse capture
func _process(_delta):
   if Input.is_action_just_pressed("capture_mouse") or \
   Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not  mouse_captured:
      mouse_captured = ! mouse_captured
      if mouse_captured: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
      else:Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# movement
func _physics_process(delta):
   if ! mouse_captured: return
   if not is_on_floor(): velocity.y -= gravity * delta
   
   if Input.is_action_just_pressed("jump") and is_on_floor(): velocity.y = JUMP_VELOCITY
   
   var input_dir = Input.get_vector("left", "right", "up", "down")
   var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
   if direction:
      velocity.x = direction.x * SPEED
      velocity.z = direction.z * SPEED
   else:
      velocity.x = move_toward(velocity.x, 0, SPEED)
      velocity.z = move_toward(velocity.z, 0, SPEED)

   move_and_slide()
