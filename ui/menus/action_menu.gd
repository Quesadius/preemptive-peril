class_name ActionMenu
extends PanelContainer
## Vertical option menu: the contextual verb menu (§9) and, in system
## mode, the end-turn menu. open() with labels; arrows move, accept
## chooses, cancel backs out. While visible it swallows input so the
## cursor and controller stay put. The programmatic API (move_selection,
## choose_selected, cancel_out) mirrors the input path for headless
## tests.

signal chosen(index: int)
signal cancelled

var _box: VBoxContainer
var _options: Array[String] = []
var _selected: int = 0


func _init() -> void:
	_box = VBoxContainer.new()
	add_child(_box)
	visible = false


## Opens with these options, selection on the first.
func open(options: Array[String]) -> void:
	_options = options.duplicate()
	_selected = 0
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.free()
	for option: String in _options:
		var label := Label.new()
		label.text = option
		_box.add_child(label)
	visible = true
	_refresh()


## Hides without emitting anything.
func close() -> void:
	visible = false


## The option labels, for tests.
func items() -> Array[String]:
	return _options.duplicate()


## The highlighted index, for tests.
func selected_index() -> int:
	return _selected


## Moves the highlight, wrapping.
func move_selection(delta: int) -> void:
	if _options.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, _options.size())
	_refresh()


## Confirms the highlighted option: closes, then emits chosen(index).
func choose_selected() -> void:
	if not visible or _options.is_empty():
		return
	var index := _selected
	close()
	chosen.emit(index)


## Backs out: closes, then emits cancelled.
func cancel_out() -> void:
	if not visible:
		return
	close()
	cancelled.emit()


func _refresh() -> void:
	for i: int in range(_box.get_child_count()):
		var label := _box.get_child(i) as Label
		label.text = ("> " if i == _selected else "  ") + _options[i]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_down", true):
		move_selection(1)
	elif event.is_action_pressed("ui_up", true):
		move_selection(-1)
	elif event.is_action_pressed("ui_accept"):
		choose_selected()
	elif event.is_action_pressed("ui_cancel"):
		cancel_out()
	else:
		return
	get_viewport().set_input_as_handled()
