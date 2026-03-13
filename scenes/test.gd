extends Node


func _ready() -> void:
	print(str(float("10")))
	var test := VDF.ParseFile("res://ds_women_a1.vmf")
	VDF.WriteFile(test, "res://test2.vmf", true)
	VDF.WriteFile(test, "res://test3.vmf", false)
