extends Control

@onready var _title: Label = %TitleLabel


func _ready() -> void:
	_title.text = "Ivy — game development workspace ready"
