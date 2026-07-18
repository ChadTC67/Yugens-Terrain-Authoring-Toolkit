@tool
extends AcceptDialog
class_name MarchingSquaresTextureEditWindow


const SINGLE_COLOR_CONTAINER := preload("uid://cf8710euu81ol")

@export var texture_preview : TextureRect

# Texture settings nodes
@export var texture_name_edit : LineEdit
@export var albedo_picker : EditorResourcePicker
@export var normal_picker : EditorResourcePicker
@export var texture_scale_slider : EditorSpinSlider

# Color settings nodes
@export var blend_mode_button : OptionButton

@export var colors_container : VBoxContainer
@export var add_color_button : Button

# Advanced settings nodes
@export var has_grass_check_box : CheckBox
@export var grass_texture_picker : EditorResourcePicker

@export var floor_noise_attributes : VBoxContainer
@export var floor_noise_check_box : CheckBox
@export var floor_strength_slider : EditorSpinSlider
@export var floor_scale_slider : EditorSpinSlider

@export var wall_noise_attributes : VBoxContainer
@export var wall_noise_check_box : CheckBox
@export var wall_strength_slider : EditorSpinSlider
@export var wall_scale_slider : EditorSpinSlider

@export var wetness_attributes : VBoxContainer
@export var wetness_check_box : CheckBox
@export var wetness_mode_button : OptionButton
@export var wetness_terrain_slider : EditorSpinSlider
@export var wetness_grass_slider : EditorSpinSlider
