class_name BuildMenu
extends PanelContainer
## Factory build list (§9): every type this facility can produce, with
## cost, unaffordable rows greyed. Choosing an unaffordable row does
## nothing. Same input/programmatic split as ActionMenu.

signal chosen(type_id: int)
signal cancelled

const GREY := Color(0.55, 0.55, 0.55)

var _box: VBoxContainer
var _rows: Array[Dictionary] = []
var _selected: int = 0


func _init() -> void:
	_box = VBoxContainer.new()
	add_child(_box)
	visible = false


## Opens with rows of {"type_id": int, "label": String, "affordable": bool}.
func open(rows: Array[Dictionary]) -> void:
	_rows = rows.duplicate()
	_selected = 0
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.free()
	for row: Dictionary in _rows:
		var label := Label.new()
		label.text = row["label"]
		if not row["affordable"]:
			label.modulate = GREY
		_box.add_child(label)
	visible = true
	_refresh()


## Hides without emitting anything.
func close() -> void:
	visible = false


## The rows, for tests.
func rows() -> Array[Dictionary]:
	return _rows.duplicate()


## The highlighted index, for tests.
func selected_index() -> int:
	return _selected


## Moves the highlight, wrapping.
func move_selection(delta: int) -> void:
	if _rows.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, _rows.size())
	_refresh()


## Confirms the highlighted row if it's affordable; otherwise stays open.
func choose_selected() -> void:
	if not visible or _rows.is_empty():
		return
	var row: Dictionary = _rows[_selected]
	if not row["affordable"]:
		return
	var type_id: int = row["type_id"]
	close()
	chosen.emit(type_id)


## Backs out: closes, then emits cancelled.
func cancel_out() -> void:
	if not visible:
		return
	close()
	cancelled.emit()


func _refresh() -> void:
	for i: int in range(_box.get_child_count()):
		var label := _box.get_child(i) as Label
		var text: String = _rows[i]["label"]
		label.text = ("> " if i == _selected else "  ") + text


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
