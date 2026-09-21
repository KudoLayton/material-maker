extends RefCounted
var owner_ref: WeakRef
var entries: Array[Dictionary] = []
var cursor := 0

func record(before: Dictionary, after: Dictionary) -> void:
	if before == after: return
	entries.resize(cursor)
	entries.append({"before":before.duplicate(true),"after":after.duplicate(true)})
	cursor += 1
	if entries.size() > 100:
		entries.pop_front()
		cursor -= 1

func can_undo() -> bool:
	return cursor > 0

func can_redo() -> bool:
	return cursor < entries.size()

func undo() -> void:
	if not can_undo(): return
	cursor -= 1
	var owner = owner_ref.get_ref()
	if owner != null: owner.apply_document(entries[cursor].before.duplicate(true))

func redo() -> void:
	if not can_redo(): return
	var owner = owner_ref.get_ref()
	if owner != null: owner.apply_document(entries[cursor].after.duplicate(true))
	cursor += 1
