data:extend{
  {type = "int-setting", name = "pq-min-players", setting_type = "runtime-global", default_value = 3, minimum_value = 1, order = "a"},
  {type = "bool-setting", name = "pq-relock-on-drop", setting_type = "runtime-global", default_value = true, order = "b"},
  {type = "string-setting", name = "pq-allowed-players", setting_type = "runtime-global", default_value = "", allow_blank = true, order = "c"},
  {type = "bool-setting", name = "pq-count-admins", setting_type = "runtime-global", default_value = true, order = "d"},
}
