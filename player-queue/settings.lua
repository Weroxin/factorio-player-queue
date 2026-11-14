data:extend{
  {type = "int-setting", name = "pq-min-players", setting_type = "runtime-global", default_value = 3, minimum_value = 1, maximum_value = 1000, order = "a"},
  {type = "bool-setting", name = "pq-relock-on-drop", setting_type = "runtime-global", default_value = true, order = "b"},
  {type = "int-setting", name = "pq-relock-grace", setting_type = "runtime-global", default_value = 5, minimum_value = 0, maximum_value = 1440, order = "ba"},
  {type = "string-setting", name = "pq-allowed-players", setting_type = "runtime-global", default_value = "", allow_blank = true, order = "c"},
  {type = "bool-setting", name = "pq-count-admins", setting_type = "runtime-global", default_value = true, order = "d"},
}
