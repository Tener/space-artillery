data:extend{
  {type = "int-setting", name = "awe-art-update-interval", setting_type = "runtime-global",
    default_value = 30, minimum_value = 1, maximum_value = 300, order = "a"},
  {type = "string-setting", name = "awe-art-min-size", setting_type = "runtime-global",
    default_value = "small", allowed_values = {"small", "medium", "big", "huge"}, order = "b"},
  {type = "int-setting", name = "awe-art-max-shells", setting_type = "runtime-global",
    default_value = 8, minimum_value = 1, maximum_value = 100, order = "c"},
  {type = "double-setting", name = "awe-art-safety-margin", setting_type = "runtime-global",
    default_value = 4, minimum_value = 0, maximum_value = 32, order = "d"},
  {type = "bool-setting", name = "awe-art-require-computer", setting_type = "runtime-global",
    default_value = true, order = "e"},
}
