class_name StatModifier
extends Resource

enum Operation { ADD, MULTIPLY }
@export var stat: StringName
@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 1.0
