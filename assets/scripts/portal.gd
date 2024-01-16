class_name Portal extends Area3D

@export var linked_portal : Portal
var disabled = false

func _on_body_entered(body):
	if !disabled:
		linked_portal.disabled = true
		body.transform = linked_portal.transform * transform.affine_inverse() * body.transform

func _on_body_exited(_body):
	disabled = false
