@tool
extends EditorPlugin

var subresource_inspect_button : Button
var subresource_tree : Tree

var locked_by_tree_selection := false
var object_pinned := false


func _enter_tree():
	subresource_inspect_button = Button.new()

	var inspector_button_box := get_editor_interface().get_inspector().get_parent().get_child(0)
	inspector_button_box.add_child(subresource_inspect_button)
	inspector_button_box.move_child(subresource_inspect_button, 0)

	subresource_inspect_button.toggle_mode = true
	subresource_inspect_button.tooltip_text = "Inspect Subresources"
	subresource_inspect_button.icon = subresource_inspect_button.get_theme_icon(&"Object", &"EditorIcons")
	subresource_inspect_button.toggled.connect(_on_button_toggled)

	var subresources_popup := PanelContainer.new()
	subresource_inspect_button.add_child(subresources_popup)
	subresources_popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	subresources_popup.top_level = true
	subresources_popup.hide()

	var new_panel_style := StyleBoxFlat.new()
	new_panel_style.set_border_width_all(3)
	new_panel_style.bg_color = subresource_inspect_button.get_theme_color("base_color", &"Editor")
	# new_panel_style.bg_color = subresource_inspect_button.get_theme_color("background", &"Editor")
	new_panel_style.border_color = subresource_inspect_button.get_theme_color("base_color", &"Editor")
	subresources_popup.add_theme_stylebox_override(&"panel", new_panel_style)

	var all_box := VBoxContainer.new()
	var buttons_box := HBoxContainer.new()
	var pin_button := Button.new()
	subresources_popup.add_child(all_box)
	all_box.add_child(buttons_box)
	buttons_box.add_child(pin_button)

	pin_button.toggle_mode = true
	pin_button.tooltip_text = "Pin inspected object"
	pin_button.icon = subresource_inspect_button.get_theme_icon(&"Pin", &"EditorIcons")
	pin_button.toggled.connect(_on_pin_toggled)

	subresource_tree = Tree.new()
	subresource_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	subresource_tree.item_selected.connect(_on_tree_item_selected)
	all_box.add_child(subresource_tree)

	get_editor_interface().get_inspector().edited_object_changed.connect(_on_button_toggled)


func _on_button_toggled(new_state : bool = subresource_inspect_button.get_child(0).visible):
	var subresources_popup : Control = subresource_inspect_button.get_child(0)
	subresources_popup.visible = new_state
	subresources_popup.size = get_editor_interface().get_base_control().size * Vector2(0.2, 0.5)
	subresources_popup.global_position = subresource_inspect_button.global_position - Vector2(subresources_popup.size.x + 6.0, -subresource_inspect_button.size.y)
	if new_state && !object_pinned && !locked_by_tree_selection:
		subresource_tree.clear()
		var edited_object := get_editor_interface().get_inspector().get_edited_object()
		var root_item := subresource_tree.create_item()
		root_item.set_text(0, "ROOT: " (edited_object.name if edited_object is Node else edited_object.resource_path))
		fill_subresource_subtree(edited_object, root_item)


func fill_subresource_subtree(of_object, tree_node : TreeItem, prop_name : String = ""):
	tree_node.set_metadata(0, of_object)
	if of_object is Resource:
		var res_name : String = of_object.resource_name
		var res_class := ""
		var result_text := ""
		if of_object.get_script() != null:
			res_class = (of_object
				.get_script()
				.resource_path
				.get_file()
				.get_basename()
				.capitalize()
			)

		else:
			res_class = of_object.get_class()

		if of_object.resource_path.find("::") == -1:
			# Resource is in FileSystem.
			tree_node.set_custom_color(0, Color(1.0, 1.0, 1.0, 0.5))
			if !res_name.is_empty():
				result_text += res_name

			else:
				result_text += of_object.resource_path.get_file().get_basename()

			result_text = "%s [%s]" % [result_text, res_class]

		else:
			# Resource is built-in.
			result_text += "[NEW] "
			if !res_name.is_empty():
				result_text = "%s%s [%s]" % [result_text, res_name, res_class]

			else:
				result_text += res_class

		tree_node.set_tooltip_text(0, of_object.resource_path + ("" if prop_name.is_empty() else "\nProperty: %s" % prop_name) + "\nType: %s" % res_class)
		tree_node.set_text(0, result_text)

	if of_object is Object:
		for x in of_object.get_property_list():
			if x.usage & PROPERTY_USAGE_EDITOR != 0:
				if x.name == &"script": continue
				var found_object = of_object[x.name]
				if found_object is Node || found_object is PackedScene: continue
				fill_subresource_subtree(found_object, subresource_tree.create_item(tree_node), x.name)

	else:
		tree_node.set_tooltip_text(0, "" if prop_name.is_empty() else "\nProperty: %s" % prop_name)
		tree_node.set_custom_color(0, Color(1.0, 1.0, 1.0, 0.1))
		if of_object == null:
			tree_node.set_text(0, prop_name + ": [empty]")

		elif of_object is Array:
			tree_node.set_text(0, prop_name + ": [array]")
			if of_object.size() == 0:
				tree_node.free()

			for x in of_object:
				if x == null || x is Resource || x is Array || x is Dictionary:
					fill_subresource_subtree(x, subresource_tree.create_item(tree_node))

		elif of_object is Dictionary:
			tree_node.set_text(0, prop_name + ": [dictionary]")
			if of_object.size() == 0:
				tree_node.free()

			for x in of_object.keys():
				if x == null || x is Resource || x is Array || x is Dictionary:
					fill_subresource_subtree(x, subresource_tree.create_item(tree_node))

			for x in of_object.values():
				if x == null || x is Resource || x is Array || x is Dictionary:
					fill_subresource_subtree(x, subresource_tree.create_item(tree_node))

		else:
			tree_node.free()


func _on_tree_item_selected():
	locked_by_tree_selection = true
	var selected_object = subresource_tree.get_selected().get_metadata(0)
	if selected_object is Resource:
		get_editor_interface().edit_resource(selected_object)

	if selected_object is Node:
		get_editor_interface().edit_node(selected_object)

	locked_by_tree_selection = false


func _on_pin_toggled(new_state : bool):
	object_pinned = new_state


func _exit_tree():
	subresource_inspect_button.queue_free()
	pass
