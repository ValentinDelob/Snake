class_name SnakeWorld
extends RefCounted

## The rules, with no dependency on nodes or rendering: a growing snake, one
## food item and deadly walls. Anything that can step this class (the game,
## a bot, a test) plays the same game.

enum Outcome { MOVED, ATE, DEAD_WALL, DEAD_SELF }

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)
const DIRECTIONS := [UP, DOWN, LEFT, RIGHT]

var width: int
var height: int
var snake: Array[Vector2i] = []
var direction: Vector2i = RIGHT
var food: Vector2i = Vector2i.ZERO
var score := 0
var steps := 0
var alive := true
var death_cell := Vector2i.ZERO

var _pending: Vector2i = RIGHT
var _rng := RandomNumberGenerator.new()


func _init(board_width: int, board_height: int, seed_value: int = 0) -> void:
	width = board_width
	height = board_height
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	reset()


func reset() -> void:
	snake = [Vector2i(width / 2, height / 2)]
	direction = RIGHT
	_pending = RIGHT
	score = 0
	steps = 0
	alive = true
	death_cell = Vector2i.ZERO
	food = spawn_food()


func head() -> Vector2i:
	return snake[0]


func length() -> int:
	return snake.size()


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


## Would the head die by moving onto this cell? The current tail is excluded:
## it moves away on the same step.
func is_lethal(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return true
	for index in range(snake.size() - 1):
		if snake[index] == cell:
			return true
	return false


func free_cells() -> Array[Vector2i]:
	var occupied := {}
	for cell in snake:
		occupied[cell] = true
	var free: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if not occupied.has(cell):
				free.append(cell)
	return free


func spawn_food() -> Vector2i:
	var candidates := free_cells()
	if candidates.is_empty():
		return head()
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## Queue a direction change, ignoring 180 degree turns.
func steer(new_direction: Vector2i) -> void:
	if new_direction != -direction:
		_pending = new_direction


## Advance the snake by one cell and report what happened.
func step() -> Outcome:
	direction = _pending
	var new_head := head() + direction
	steps += 1

	if not is_inside(new_head):
		alive = false
		death_cell = new_head
		return Outcome.DEAD_WALL

	for index in range(snake.size() - 1):
		if snake[index] == new_head:
			alive = false
			death_cell = new_head
			return Outcome.DEAD_SELF

	snake.insert(0, new_head)
	if new_head == food:
		score += 1
		food = spawn_food()
		return Outcome.ATE

	snake.remove_at(snake.size() - 1)
	return Outcome.MOVED


static func is_death(outcome: Outcome) -> bool:
	return outcome == Outcome.DEAD_WALL or outcome == Outcome.DEAD_SELF


static func turn_left(dir: Vector2i) -> Vector2i:
	return Vector2i(dir.y, -dir.x)


static func turn_right(dir: Vector2i) -> Vector2i:
	return Vector2i(-dir.y, dir.x)
