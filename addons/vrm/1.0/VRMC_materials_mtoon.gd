extends GLTFDocumentExtension

enum DebugMode {
	None = 0,
	Normal = 1,
	LitShadeRate = 2,
}

enum OutlineColorMode {
	FixedColor = 0,
	MixedLight3Ding = 1,
}

enum OutlineWidthMode {
	None = 0,
	WorldCoordinates = 1,
	ScreenCoordinates = 2,
}

enum RenderMode {
	Opaque = 0,
	Cutout = 1,
	Transparent = 2,
	TransparentWithZWrite = 3,
}

enum CullMode {
	Off = 0,
	Front = 1,
	Back = 2,
}

func _import_preflight(state: GLTFState, extensions = PackedStringArray()) -> Error:
	if extensions.has("VRMC_materials_mtoon"):
		return OK
	return ERR_INVALID_DATA

func _prepare_gltf_texture(gltf_samplers: Array[GLTFTextureSampler], gltf_textures: Array[GLTFTexture], texture_dictionary: Dictionary, tex: Texture2D) -> int:
	var gltf_sampler: GLTFTextureSampler = GLTFTextureSampler.new()
	# FIXME: We do not currently have a way to set texture wrap / repeat settings for each shader, so we use defaults for now
	var sampler_idx: int = len(gltf_samplers)
	gltf_samplers.push_back(gltf_sampler)

	var gltf_tex: GLTFTexture = GLTFTexture.new()
	# Ok so this is is yucky and gross. There is no way to intercept between creation of Standard Materials
	# and craetion of the images array, and also no way to alter the cached images array.
	# So, all GLTFTexture objects point to 0. Then, we fill these in post, since some images may reference
	# textures which were added internally, and we can't know their index until later.
	gltf_tex.src_image = 0
	#gltf_tex.src_image = len(gltf_images)
	#gltf_images.push_back(tex)
	gltf_tex.sampler = sampler_idx
	var texture_idx: int = len(gltf_textures)
	gltf_textures.push_back(gltf_tex)
	texture_dictionary[texture_idx] = tex
	return texture_idx

func _prepare_material_for_export(gltf_samp: Array[GLTFTextureSampler], gltf_tex: Array[GLTFTexture], texdic: Dictionary, standard_textures: Dictionary, mtoon_material: ShaderMaterial) -> StandardMaterial3D:
	var shader_name = mtoon_material.shader.resource_path.get_file().get_basename()
	var has_cutout = shader_name.find("_cutout") > 0
	var has_trans = shader_name.find("_trans") > 0
	var has_zwrite = shader_name.find("_zwrite") > 0
	var has_cull_off = shader_name.find("_cull_off") > 0
	var has_outline = false
	if mtoon_material.next_pass != null and mtoon_material.next_pass.shader != null:
		var outline_shader = mtoon_material.next_pass.shader.resource_path.get_file().get_basename()
		has_outline = outline_shader.find("mtoon_outline") > 0

	var standard_mat: StandardMaterial3D = StandardMaterial3D.new()
	standard_mat.albedo_color = mtoon_material.get_shader_parameter("_Color")
	standard_mat.albedo_texture = mtoon_material.get_shader_parameter("_MainTex")
	standard_textures[standard_mat.albedo_texture] = true
	var col = mtoon_material.get_shader_parameter("_EmissionColor")
	if typeof(col) == TYPE_COLOR:
		col.a = 1.0
		standard_mat.emission_enabled =  mtoon_material.get_shader_parameter("_EmissionMap") != null or !col.is_equal_approx(Color.BLACK)
		standard_mat.emission_texture = mtoon_material.get_shader_parameter("_EmissionMap")
		standard_textures[standard_mat.emission_texture] = true
		standard_mat.emission = col
	standard_mat.normal_texture = mtoon_material.get_shader_parameter("_BumpMap")
	standard_textures[standard_mat.normal_texture] = true
	standard_mat.normal_enabled = mtoon_material.get_shader_parameter("_BumpMap") != null
	standard_mat.normal_scale = mtoon_material.get_shader_parameter("_BumpScale")
	if has_trans:
		standard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif has_cutout:
		standard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		standard_mat.alpha_scissor_threshold = mtoon_material.get_shader_parameter("_Cutoff")
	else:
		standard_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	var tex_repeat: Variant = mtoon_material.get_shader_parameter("_MainTex_ST")
	if typeof(tex_repeat) == TYPE_PLANE:
		standard_mat.uv1_scale = Vector3(tex_repeat.x, tex_repeat.y, 0)
		standard_mat.uv1_offset = Vector3(tex_repeat.z, tex_repeat.d, 0)
	elif typeof(tex_repeat) == TYPE_VECTOR4:
		standard_mat.uv1_scale = Vector3(tex_repeat.x, tex_repeat.y, 0)
		standard_mat.uv1_offset = Vector3(tex_repeat.z, tex_repeat.w, 0)

	var additional_textures = {}
	if mtoon_material.get_shader_parameter("_ShadeTexture") != null:
		additional_textures["shadeMultiplyTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_ShadeTexture"))
	if mtoon_material.get_shader_parameter("_ShadingGradeTexture") != null:
		additional_textures["shadingShiftTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_ShadingGradeTexture"))
	if mtoon_material.get_shader_parameter("_RimTexture") != null:
		additional_textures["rimMultiplyTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_RimTexture"))
	if mtoon_material.get_shader_parameter("_SphereAdd") != null:
		additional_textures["matcapTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_SphereAdd"))
	if mtoon_material.get_shader_parameter("_UvAnimMaskTexture") != null:
		additional_textures["uvAnimationMaskTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_UvAnimMaskTexture"))
	if mtoon_material.get_shader_parameter("_OutlineWidthTexture") != null:
		additional_textures["outlineWidthMultiplyTexture"] = _prepare_gltf_texture(gltf_samp, gltf_tex, texdic, mtoon_material.get_shader_parameter("_OutlineWidthTexture"))

	standard_mat.set_meta("mtoon_material", mtoon_material)
	standard_mat.set_meta("additional_textures", additional_textures)
	'''
	_assign_color(new_mat, false, "_ShadeColor", vrm_mat_props.get("shadeColorFactor", [0,0,0]))
	_assign_color(new_mat, false, "_RimColor", vrm_mat_props.get("parametricRimColorFactor", [0,0,0]))
	# FIXME: _MatcapColor does not exist!!
	_assign_color(new_mat, false, "_MatcapColor", vrm_mat_props.get("matcapFactor", [1,1,1]))
	_assign_color(new_mat, false, "_OutlineColor", vrm_mat_props.get("outlineColorFactor", [0,0,0,1]))

	var outline_width_idx: float = 0
	if outline_width_mode == "worldCoordinates":
		outline_width_idx = 1
	if outline_width_mode == "screenCoordinates":
		outline_width_idx = 2
	_assign_property(new_mat, "_OutlineWidthMode", outline_width_idx)

	#"_ReceiveShadowRate": ["Shadow Receive", "Texture (R) * Rate. White is Default. Black attenuates shadows."],
	#"_LightColorAttenuation": ["Light Color Atten", "Light Color Attenuation"],
	#"_IndirectLightIntensity": ["GI Intensity", "Indirect Light Intensity"],
	#"_OutlineScaledMaxDistance": ["Outline Scaled Dist", "Width Scaled Max Distance"],

	_assign_property(new_mat, "_ShadeToony", vrm_mat_props.get("shadingToonyFactor", 0.9))
	_assign_property(new_mat, "_ShadeShift", vrm_mat_props.get("shadingShiftFactor", 0.0))
	_assign_property(new_mat, "_ShadingGradeRate", vrm_mat_props.get("shadeMultiplyTexture", {}).get("scale", 1.0))
	_assign_property(new_mat, "_ReceiveShadowRate", 1.0) # 0 disables directional light shadows. no longer supported?
	_assign_property(new_mat, "_LightColorAttenuation", 0.0) # not useful
	_assign_property(new_mat, "_IndirectLightIntensity", 1.0 - vrm_mat_props.get("giEqualizationFactor", 0.9))
	_assign_property(new_mat, "_OutlineScaledMaxDistance", 99.0) # FIXME: different calulcation
	_assign_property(new_mat, "_RimLightingMix", vrm_mat_props.get("rimLightingMixFactor", 0.0))
	_assign_property(new_mat, "_RimFresnelPower", vrm_mat_props.get("parametricRimFresnelPowerFactor", 1.0))
	_assign_property(new_mat, "_RimLift", vrm_mat_props.get("parametricRimLiftFactor", 0.0))
	_assign_property(new_mat, "_OutlineWidth", vrm_mat_props.get("outlineWidthFactor", 0.0))
	_assign_property(new_mat, "_OutlineColorMode", 1.0) # MixedLighting always. FixedColor if outlineLightingMixFactor==0
	_assign_property(new_mat, "_OutlineLightingMix", vrm_mat_props.get("outlineLightingMixFactor", 1.0))
	_assign_property(new_mat, "_UvAnimScrollX", vrm_mat_props.get("uvAnimationScrollXSpeedFactor", 0.0))
	_assign_property(new_mat, "_UvAnimScrollY", vrm_mat_props.get("uvAnimationScrollYSpeedFactor", 0.0))
	_assign_property(new_mat, "_UvAnimRotation", vrm_mat_props.get("uvAnimationRotationSpeedFactor", 0.0))
	'''
	return standard_mat

func _export_preflight(state: GLTFState, root: Node) -> Error:
	var materials: Dictionary = {}
	var meshes = root.find_children("*", "ImporterMeshInstance3D")
	var texdic: Dictionary = {}
	var standard_textures: Dictionary = {}
	var gltf_samp: Array[GLTFTextureSampler] = state.texture_samplers
	var gltf_tex: Array[GLTFTexture] = state.textures
	var uses_mtoon: bool = false
	for meshx in meshes:
		var mesh: ImporterMeshInstance3D = meshx
		for m in range(mesh.mesh.get_surface_count()):
			var mat: Material = mesh.mesh.get_surface_material(m)
			if mat is ShaderMaterial:
				if mat.shader != null and mat.shader.resource_path.get_file().starts_with("mtoon_"):
					uses_mtoon = true
					if not materials.has(mat):
						materials[mat] = _prepare_material_for_export(gltf_samp, gltf_tex, texdic, standard_textures, mat)
					mesh.mesh.set_surface_material(m, materials[mat])
	meshes = root.find_children("*", "MeshInstance3D")
	for meshx in meshes:
		var mesh: MeshInstance3D = meshx
		for m in range(mesh.mesh.get_surface_count()):
			var mat: Material = mesh.get_surface_override_material(m)
			if mat == null:
				mat = mesh.mesh.surface_get_material(m)
			if mat is ShaderMaterial:
				if mat.shader != null and mat.shader.resource_path.get_file().starts_with("mtoon_"):
					uses_mtoon = true
					if not materials.has(mat):
						materials[mat] = _prepare_material_for_export(gltf_samp, gltf_tex, texdic, standard_textures, mat)
					mesh.set_surface_override_material(m, materials[mat])

	if uses_mtoon:
		state.add_used_extension("VRMC_materials_mtoon", false)

	state.texture_samplers = gltf_samp
	state.textures = gltf_tex
	var unique_images_to_add: Dictionary = {}
	for tex in texdic.values():
		if not standard_textures.has(tex):
			unique_images_to_add[tex] = true
	var gltf_images: Array[Texture2D] = state.images
	for tex in unique_images_to_add:
		gltf_images.push_back(tex)
	state.images = gltf_images # Any textures not used by a StandardMaterial3D are our responsibility.
	state.set_meta("texture_dictionary", texdic)
	return OK

func _export_post(state: GLTFState) -> Error:
	return OK

func _vrm_get_texture_info(gltf_images: Array, vrm_mat_props: Dictionary, unity_tex_name: String) -> Dictionary:
	var texture_info: Dictionary = {}
	texture_info["tex"] = null
	texture_info["offset"] = Vector3(0.0, 0.0, 0.0)
	texture_info["scale"] = Vector3(1.0, 1.0, 1.0)
	if vrm_mat_props["textureProperties"].has(unity_tex_name):
		var mainTexId: int = vrm_mat_props["textureProperties"][unity_tex_name]
		var mainTexImage: Texture2D = gltf_images[mainTexId]
		texture_info["tex"] = mainTexImage
	if vrm_mat_props["vectorProperties"].has(unity_tex_name):
		var offsetScale: Array = vrm_mat_props["vectorProperties"][unity_tex_name]
		texture_info["offset"] = Vector3(offsetScale[0], offsetScale[1], 0.0)
		texture_info["scale"] = Vector3(offsetScale[2], offsetScale[3], 1.0)
	return texture_info


func _vrm_get_float(vrm_mat_props: Dictionary, key: String, def: float) -> float:
	return vrm_mat_props["floatProperties"].get(key, def)


func _assign_property(new_mat: ShaderMaterial, property_name: String, property_value: Variant) -> void:
	new_mat.set_shader_parameter(property_name, property_value)
	if new_mat.next_pass != null:
		new_mat.next_pass.set_shader_parameter(property_name, property_value)

func _assign_texture(new_mat: ShaderMaterial, gltf_images: Array, texture_name: String, texture_info: Dictionary) -> void:
	# TODO: something with texCoord
	# TODO: something with extensions[KHR_texture_transform].texCoord
	# TODO: something with extensions[KHR_texture_transform].offset/scale?
	var tex: Texture2D = null
	if texture_info.has("index"):
		tex = gltf_images[texture_info["index"]]

	_assign_property(new_mat, texture_name, tex)

func _assign_color(new_mat: ShaderMaterial, has_alpha: bool, property_name: String, color_array: Array) -> void:
	var col: Color
	if has_alpha:
		col = Color(color_array[0], color_array[1], color_array[2], color_array[3])
	else:
		col = Color(color_array[0], color_array[1], color_array[2])

	_assign_property(new_mat, property_name, col)

func _process_vrm_material(orig_mat: Material, gltf_images: Array, mat_props: Dictionary, vrm_mat_props: Dictionary) -> Material:

	if vrm_mat_props.get("specVersion", "") != "1.0":
		push_warning("Unsupported VRM MToon specVersion " + str(vrm_mat_props.get("specVersion", "")))

	var blend_extension: String = ""
	var alpha_mode: String = mat_props.get("alphaMode", "OPAQUE")
	if alpha_mode == "MASK":
		blend_extension = "_cutout"
	if alpha_mode == "BLEND":
		blend_extension = "_trans"
		if vrm_mat_props.get("transparentWithZWrite", false) == true:
			blend_extension += "_zwrite"

	var outline_width_mode: String = vrm_mat_props.get("outlineWidthMode", "none")

	var mtoon_shader_base_path: String = "res://addons/Godot-MToon-Shader/mtoon"

	var godot_outline_shader_name: String = ""
	if outline_width_mode != "none":
		godot_outline_shader_name = mtoon_shader_base_path + "_outline" + blend_extension

	var godot_shader_name = mtoon_shader_base_path + blend_extension
	if mat_props.get("doubleSided", false) == true:
		godot_shader_name += "_cull_off"

	var godot_shader: Shader = ResourceLoader.load(godot_shader_name + ".gdshader")

	var new_mat : ShaderMaterial = ShaderMaterial.new()
	new_mat.resource_name = orig_mat.resource_name
	new_mat.shader = godot_shader

	var godot_shader_outline: Shader = null
	if !godot_outline_shader_name.is_empty():
		godot_shader_outline = ResourceLoader.load(godot_outline_shader_name + ".gdshader")

	var outline_mat: ShaderMaterial = null
	if godot_shader_outline != null:
		outline_mat = ShaderMaterial.new()
		outline_mat.resource_name = orig_mat.resource_name + "(Outline)"
		outline_mat.shader = godot_shader_outline
		new_mat.next_pass = outline_mat

	var base_color_texture = mat_props.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
	var khr_texture_transform = base_color_texture.get("extensions", {}).get("KHR_texture_transform", {})
	var offset = khr_texture_transform.get("offset", [0.0, 0.0])
	var scale = khr_texture_transform.get("scale", [1.0, 1.0])
	# texCoord does not seem implemented in MToon.
	# KHR_texture_transform also has its own texCoord.
	# KHR_texture_transform is only supported by `baseColorTexture`
	var texture_repeat = Vector4(scale[0], scale[1], offset[0], offset[1])

	_assign_texture(new_mat, gltf_images, "_MainTex", base_color_texture)
	_assign_texture(new_mat, gltf_images, "_ShadeTexture", vrm_mat_props.get("shadeMultiplyTexture", {}))
	_assign_texture(new_mat, gltf_images, "_ShadingGradeTexture", vrm_mat_props.get("shadingShiftTexture", {}))
	_assign_texture(new_mat, gltf_images, "_BumpMap", mat_props.get("normalTexture", {}))
	_assign_texture(new_mat, gltf_images, "_EmissionMap", mat_props.get("emissiveTexture", {}))
	# TODO: implement emission factor?
	# var vrmc_emissive: Dictionary = mat_props.get("extensions", {}).get("VRMC_materials_hdr_emissiveMultiplier", {})
	# var khr_emissive: Dictionary = mat_props.get("extensions", {}).get("KHR_materials_emissive_strength", {})

	_assign_texture(new_mat, gltf_images, "_RimTexture", vrm_mat_props.get("rimMultiplyTexture", {}))
	_assign_texture(new_mat, gltf_images, "_SphereAdd", vrm_mat_props.get("matcapTexture", {}))
	_assign_texture(new_mat, gltf_images, "_UvAnimMaskTexture", vrm_mat_props.get("uvAnimationMaskTexture", {}))
	_assign_texture(new_mat, gltf_images, "_OutlineWidthTexture", vrm_mat_props.get("outlineWidthMultiplyTexture", {}))

	_assign_color(new_mat, true, "_Color", mat_props.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1,1,1,1]))
	_assign_color(new_mat, false, "_ShadeColor", vrm_mat_props.get("shadeColorFactor", [0,0,0]))
	_assign_color(new_mat, false, "_RimColor", vrm_mat_props.get("parametricRimColorFactor", [0,0,0]))
	# FIXME: _MatcapColor does not exist!!
	_assign_color(new_mat, false, "_MatcapColor", vrm_mat_props.get("matcapFactor", [1,1,1]))
	_assign_color(new_mat, false, "_OutlineColor", vrm_mat_props.get("outlineColorFactor", [0,0,0,1]))
	_assign_color(new_mat, false, "_EmissionColor", mat_props.get("emissiveFactor", [0,0,0]))

	_assign_property(new_mat, "_MainTex_ST", texture_repeat)

	var outline_width_idx: float = 0
	if outline_width_mode == "worldCoordinates":
		outline_width_idx = 1
	if outline_width_mode == "screenCoordinates":
		outline_width_idx = 2
	_assign_property(new_mat, "_OutlineWidthMode", outline_width_idx)

	#"_ReceiveShadowRate": ["Shadow Receive", "Texture (R) * Rate. White is Default. Black attenuates shadows."],
	#"_LightColorAttenuation": ["Light Color Atten", "Light Color Attenuation"],
	#"_IndirectLightIntensity": ["GI Intensity", "Indirect Light Intensity"],
	#"_OutlineScaledMaxDistance": ["Outline Scaled Dist", "Width Scaled Max Distance"],

	_assign_property(new_mat, "_AlphaCutoutEnable", 1.0 if alpha_mode == "MASK" else 0.0)
	_assign_property(new_mat, "_BumpScale", mat_props.get("normalTexture", {}).get("scale", 1.0))
	_assign_property(new_mat, "_Cutoff", mat_props.get("alphaCutoff", 0.5))
	_assign_property(new_mat, "_ShadeToony", vrm_mat_props.get("shadingToonyFactor", 0.9))
	_assign_property(new_mat, "_ShadeShift", vrm_mat_props.get("shadingShiftFactor", 0.0))
	_assign_property(new_mat, "_ShadingGradeRate", vrm_mat_props.get("shadingShiftTexture", {}).get("scale", 1.0))
	_assign_property(new_mat, "_ReceiveShadowRate", 1.0) # 0 disables directional light shadows. no longer supported?
	_assign_property(new_mat, "_LightColorAttenuation", 0.0) # not useful
	_assign_property(new_mat, "_IndirectLightIntensity", 1.0 - vrm_mat_props.get("giEqualizationFactor", 0.9))
	_assign_property(new_mat, "_OutlineScaledMaxDistance", 99.0) # FIXME: different calulcation
	_assign_property(new_mat, "_RimLightingMix", vrm_mat_props.get("rimLightingMixFactor", 0.0))
	_assign_property(new_mat, "_RimFresnelPower", vrm_mat_props.get("parametricRimFresnelPowerFactor", 1.0))
	_assign_property(new_mat, "_RimLift", vrm_mat_props.get("parametricRimLiftFactor", 0.0))
	_assign_property(new_mat, "_OutlineWidth", vrm_mat_props.get("outlineWidthFactor", 0.0))
	_assign_property(new_mat, "_OutlineColorMode", 1.0) # MixedLighting always. FixedColor if outlineLightingMixFactor==0
	_assign_property(new_mat, "_OutlineLightingMix", vrm_mat_props.get("outlineLightingMixFactor", 1.0))
	_assign_property(new_mat, "_UvAnimScrollX", vrm_mat_props.get("uvAnimationScrollXSpeedFactor", 0.0))
	_assign_property(new_mat, "_UvAnimScrollY", vrm_mat_props.get("uvAnimationScrollYSpeedFactor", 0.0))
	_assign_property(new_mat, "_UvAnimRotation", vrm_mat_props.get("uvAnimationRotationSpeedFactor", 0.0))

	if alpha_mode == "BLEND":
		var delta_render_queue = vrm_mat_props.get("renderQueueOffsetNumbers", 0)
		if vrm_mat_props.get("transparentWithZWrite", false) == true:
			# renderQueueOffsetNumbers range for this case is 0 to +9
			# must be rendered before transparentWithZWrite==false
			# transparentWithZWrite==false has renderQueueOffsetNumbers between -9 and 0
			# so we need these to be below that.
			delta_render_queue -= 19
		# render_priority only makes sense for transparent materials.
		new_mat.render_priority = delta_render_queue
		if outline_mat != null:
			outline_mat.render_priority = delta_render_queue
	else:
		new_mat.render_priority = 0
		if outline_mat != null:
			outline_mat.render_priority = 0
		
	return new_mat


# Called when the node enters the scene tree for the first time.
func _import_post(gstate, root):
	var images = gstate.get_images()
	#print(images)
	var materials: Array = gstate.get_materials()
	var materials_json: Array[Dictionary] = []
	var materials_vrm_json: Array[Dictionary] = []
	var spatial_to_shader_mat: Dictionary = {}

	for i in range(materials.size()):
		var material: Material = materials[i]
		var json_material = gstate.json["materials"][i]
		materials_json.push_back(json_material)
		var extensions: Dictionary = json_material.get("extensions", {})
		materials_vrm_json.push_back(extensions.get("VRMC_materials_mtoon", {}))
		
	# Material conversions
	for i in range(materials.size()):
		var oldmat: Material = materials[i]
		if oldmat is ShaderMaterial:
			# Indicates that the user asked to keep existing materials. Avoid changing them.
			print("Material " + str(i) + ": " + str(oldmat.resource_name) + " already is shader.")
			continue
		var newmat: Material = oldmat
		var mat_props: Dictionary = materials_json[i]
		var vrm_mat_props: Dictionary = materials_vrm_json[i]
		newmat = _process_vrm_material(newmat, images, mat_props, vrm_mat_props)
		spatial_to_shader_mat[oldmat] = newmat
		spatial_to_shader_mat[newmat] = newmat
		# print("Replacing shader " + str(oldmat) + "/" + str(oldmat.resource_name) + " with " + str(newmat) + "/" + str(newmat.resource_name))
		materials[i] = newmat
		var oldpath = oldmat.resource_path
		if oldpath.is_empty():
			continue
		newmat.take_over_path(oldpath)
		ResourceSaver.save(newmat, oldpath)
	gstate.set_materials(materials)

	var meshes = gstate.get_meshes()
	for i in range(meshes.size()):
		var gltfmesh: GLTFMesh = meshes[i]
		var mesh = gltfmesh.mesh
		mesh.set_blend_shape_mode(Mesh.BLEND_SHAPE_MODE_NORMALIZED)
		for surf_idx in range(mesh.get_surface_count()):
			var surfmat = mesh.get_surface_material(surf_idx)
			if spatial_to_shader_mat.has(surfmat):
				mesh.set_surface_material(surf_idx, spatial_to_shader_mat[surfmat])
			else:
				printerr("Mesh " + str(i) + " material " + str(surf_idx) + " name " + str(surfmat.resource_name) + " has no replacement material.")

	# FIXME: due to head duplication, do we now have some meshes which are not in gltf state?
