class_name FaunaAnchor
extends RefCounted

var kind: FaunaConstants.AnchorKind = FaunaConstants.AnchorKind.FLOWER
var local_transform: Transform3D = Transform3D.IDENTITY
## 0 at hero hard exclusion; 1 outside soft fade band (SD-FAUNA-5).
var hero_weight: float = 1.0
