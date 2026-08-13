class_name TestCase
extends RefCounted

## The whole test framework. Deliberately about sixty lines: the repo has one thing worth testing
## headlessly — the feel model — and pulling in a framework to test it would be more machinery than
## the thing under test.
##
## Subclass, add methods named `test_*`, run with tools/track/test.ps1 (or test.sh).

var _failures: PackedStringArray = PackedStringArray()
var _assertions: int = 0
var _current: String = ""


## Overridden by each suite, so failure lines say which file to open. A method rather than
## get_script().get_global_name(): get_script() returns Variant, and the project's warnings table
## makes casting a Variant to Script an error.
func suite_name() -> String:
	return "TestCase"


## Runs every `test_*` method on this instance and returns the failure lines.
func run() -> PackedStringArray:
	for method: Dictionary in get_method_list():
		var name: String = str(method.get("name", ""))
		if not name.begins_with("test_"):
			continue
		_current = name
		var _discard: Variant = callv(name, [])
	return _failures


func assertion_count() -> int:
	return _assertions


func fail(message: String) -> void:
	_assertions += 1
	_record(message)


func check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_record(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %.4f +/- %.4f, got %.4f)" % [message, expected, tolerance, actual])


func check_greater(actual: float, threshold: float, message: String) -> void:
	check(actual > threshold, "%s (expected > %.4f, got %.4f)" % [message, threshold, actual])


func check_less(actual: float, threshold: float, message: String) -> void:
	check(actual < threshold, "%s (expected < %.4f, got %.4f)" % [message, threshold, actual])


func _record(message: String) -> void:
	_failures.append("%s / %s: %s" % [suite_name(), _current, message])
