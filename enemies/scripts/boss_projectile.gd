class_name BossProjectile
extends HurtBox

## A boss's thrown shot. Built in code by BossRangedAttack and parented to the
## boss (top_level), never to HordeEnemies: that container's child count gates
## the stage clear. Freed on the player, on a wall or prop, or at its lifetime.
## Walls are found by sweeping the shape each tick (cast_motion), not by
## body_entered: in testing a shard flew through an arena Blockers shape with
## no overlap reported, and a sweep cannot tunnel either.

const GROUP := &"boss_projectile"
const OUTLINE := Color(0.08, 0.05, 0.1)
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)
## Shots fly at chest height; the shadow marks where they are on the ground.
const SHADOW_DROP := 12.0
## Picked to stand out on the boss's own arena: purple on Meadow green, white
## on the Ruins, steel on the Ashen Camp, deep blue on Frozen Hollow snow.
const COLORS := {
	&"glob": [Color(0.72, 0.28, 0.9), Color(1.0, 0.72, 1.0)],
	&"bone": [Color(0.95, 0.92, 0.82), Color(1.0, 1.0, 1.0)],
	&"axe": [Color(0.62, 0.28, 0.14), Color(0.86, 0.89, 0.94)],
	&"shard": [Color(0.12, 0.42, 1.0), Color(0.72, 0.95, 1.0)],
}
const RADIUS := {&"glob": 5.0, &"bone": 4.0, &"axe": 7.0, &"shard": 4.0}
const SPIN_SPEED := 12.0

var velocity: Vector2 = Vector2.ZERO
var kind: StringName = &"glob"
var lifetime: float = 3.0
var _age: float = 0.0
var _circle: CircleShape2D


func setup(shot_kind: StringName, shot_velocity: Vector2, shot_damage: int, shot_lifetime: float) -> void:
	kind = shot_kind if COLORS.has(shot_kind) else &"glob"
	velocity = shot_velocity
	damage = shot_damage
	lifetime = shot_lifetime
	top_level = true
	z_index = 5
	collision_layer = 0
	collision_mask = 2  # PlayerHurt; walls are swept in _physics_process
	monitorable = false
	rotation = shot_velocity.angle()
	_circle = CircleShape2D.new()
	_circle.radius = RADIUS[kind]
	var shape := CollisionShape2D.new()
	shape.shape = _circle
	add_child(shape)
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	if _hits_wall(step):
		queue_free()
		return
	position += step
	if kind == &"axe":
		rotation += SPIN_SPEED * delta
		queue_redraw()  # the ground shadow must stay below while it spins
	_age += delta
	if _age >= lifetime:
		queue_free()


func _area_entered(a: Area2D) -> void:
	if a is HitBox:
		super(a)
		queue_free()


## Overlapping a wall now (cast_motion ignores a shape that starts inside one,
## e.g. a shot launched against a prop), or touching one during this step.
func _hits_wall(step: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _circle
	query.collision_mask = 16  # Walls
	query.transform = Transform2D(0.0, global_position)
	if not space.intersect_shape(query, 1).is_empty():
		return true
	query.motion = step
	var hit := space.cast_motion(query)
	return not hit.is_empty() and hit[0] < 1.0


## Whole-pixel blocks with a 1 px dark outline, pointing along +x, over a
## ground shadow drawn unrotated.
func _draw() -> void:
	draw_set_transform(Vector2(0.0, SHADOW_DROP).rotated(-rotation), -rotation, Vector2.ONE)
	draw_rect(Rect2(-5, -1, 10, 2), SHADOW)
	draw_rect(Rect2(-3, -2, 6, 4), SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c: Array = COLORS[kind]
	match kind:
		&"glob":
			draw_rect(Rect2(-6, -4, 12, 8), OUTLINE)
			draw_rect(Rect2(-5, -5, 10, 10), OUTLINE)
			draw_rect(Rect2(-5, -3, 10, 6), c[0])
			draw_rect(Rect2(-4, -4, 8, 8), c[0])
			draw_rect(Rect2(-3, -3, 3, 2), c[1])
		&"bone":
			draw_rect(Rect2(-11, -2, 18, 4), OUTLINE)
			draw_rect(Rect2(6, -4, 7, 8), OUTLINE)
			draw_rect(Rect2(-10, -1, 17, 2), c[0])
			draw_rect(Rect2(7, -3, 5, 6), c[1])
		&"axe":
			draw_rect(Rect2(-9, -2, 14, 4), OUTLINE)
			draw_rect(Rect2(2, -7, 8, 14), OUTLINE)
			draw_rect(Rect2(-8, -1, 12, 2), c[0])
			draw_rect(Rect2(3, -6, 6, 12), c[1])
			draw_rect(Rect2(8, -5, 1, 10), Color.WHITE)
		&"shard":
			draw_rect(Rect2(-8, -3, 14, 6), OUTLINE)
			draw_rect(Rect2(6, -2, 3, 4), OUTLINE)
			draw_rect(Rect2(-7, -2, 13, 4), c[0])
			draw_rect(Rect2(-4, -1, 9, 2), c[1])
			draw_rect(Rect2(6, -1, 2, 2), c[1])
