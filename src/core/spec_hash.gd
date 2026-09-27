class_name SpecHash
extends RefCounted

## Content identity for geometry that is generated from a spec resource rather than
## loaded from a file (ivy-9xp).
##
## `MeshSdf` keys its caches on a hash of the collision GLB's bytes (SD-MESH-9). Procedural
## buildings have no file to hash, so their identity has to come from the values that define
## the shape instead — every exported field of `WallSpec` / `TowerSpec`.
##
## Read reflectively, not from a maintained name list, because a hand-written list is the
## failure mode this exists to prevent: adding `@export var lip_thickness` to a spec without
## remembering to extend a list would leave two different buildings sharing one cache key.
## Reflection means a new field changes the hash whether or not anyone thought about it.

const HASH_BYTES := 32


## 32-byte identity over `res`'s exported fields, namespaced by `tag` so two spec types that
## happen to hold identical numbers cannot collide.
static func of(tag: String, res: Resource) -> PackedByteArray:
	if res == null:
		return PackedByteArray()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(tag.to_utf8_buffer())
	ctx.update(serialize(res).to_utf8_buffer())
	return ctx.finish()


## Stable text form of every exported field, sorted by name. Separate from `of()` so a
## mismatch can be printed and diffed rather than compared as opaque bytes.
static func serialize(res: Resource) -> String:
	var parts: PackedStringArray = []
	for prop in res.get_property_list():
		if not _is_exported(prop):
			continue
		var name: String = prop["name"]
		parts.append("%s=%s" % [name, format_value(res.get(name))])
	parts.sort()
	return "|".join(parts)


## Mirrors `IvyParams._format_value` — fixed decimals rather than `str()`, so the text form
## does not depend on Godot's float-printing shortest-round-trip behaviour.
static func format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_FLOAT:
			return "%.9f" % v
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_COLOR:
			var c: Color = v
			return "%.6f,%.6f,%.6f,%.6f" % [c.r, c.g, c.b, c.a]
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "%.9f,%.9f" % [v2.x, v2.y]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "%.9f,%.9f,%.9f" % [v3.x, v3.y, v3.z]
		TYPE_OBJECT:
			# `str(object)` embeds an instance id that changes every run, which would quietly
			# give one spec a different identity on every load and make the cache never hit.
			# Say so instead: a spec that grows a nested resource needs a case added here.
			push_error("SpecHash: cannot hash object-valued field %s; add a case for it" % str(v))
			return "<unhashable-object>"
		_:
			return str(v)


static func _is_exported(prop: Dictionary) -> bool:
	var usage: int = prop["usage"]
	if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
		return false
	# Storage rules out the editor-only group/category pseudo-properties, which carry no value.
	return (usage & PROPERTY_USAGE_STORAGE) != 0
