extends Node2D

func _ready():
	var rd = RenderingServer.get_rendering_device()
	
	# Read raw SPIR-V bytes
	var f = FileAccess.open("res://shaders/compute_noise.spv", FileAccess.READ)
	if not f:
		print("ERROR: cannot open .spv")
		queue_free()
		return
	var raw = f.get_buffer(f.get_length())
	f.close()
	print("SPV size: ", raw.size())
	
	# Convert to PackedInt32Array (SPIR-V is uint32 words)
	var words = raw.to_int32_array()
	print("Words: ", words.size(), " first: ", "%08x" % words[0])
	
	# Try creating shader via RDShaderSPIRV  
	var spirv = RDShaderSPIRV.new()
	
	# Check all methods
	print("\nRDShaderSPIRV methods:")
	for m in spirv.get_method_list():
		print("  ", m)
	
	# Check property hints
	for p in spirv.get_property_list():
		if p.name.begins_with("_"):
			continue
		print("  PROP: ", p.name, " type=", p.type, " hint=", p.hint_string)
	
	queue_free()
