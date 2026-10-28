"""NPOT opt-in on a caller-owned transient Interchange pipeline only."""
import unreal

def enable_owned_npot_textures(pipeline, set_option=None):
    if not isinstance(pipeline, unreal.InterchangeGenericAssetsPipeline):
        raise TypeError("Expected an owned InterchangeGenericAssetsPipeline")
    if not pipeline.get_path_name().startswith("/Engine/Transient."):
        raise ValueError("Refusing to modify a saved pipeline asset or class default")
    material = pipeline.get_editor_property("material_pipeline")
    texture = material.get_editor_property("texture_pipeline")
    before = texture.get_editor_property("allow_non_power_of_two")
    if type(before) is not bool:
        raise TypeError("Native NPOT policy must be bool")
    if set_option is None:
        texture.set_editor_property("allow_non_power_of_two", True)
    else:
        set_option(texture, "allow_non_power_of_two", True)
    after = texture.get_editor_property("allow_non_power_of_two")
    if after is not True:
        raise RuntimeError("Owned texture NPOT opt-in readback failed")
    return {"pipeline": pipeline.get_path_name(),
            "texture_pipeline": texture.get_path_name(),
            "npot_before": before, "npot_after": after}
