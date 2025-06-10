defmodule TextDrop.Views.Home do
  require EEx

  EEx.function_from_file(:def, :index, "lib/text_drop/views/home/index.html.eex", [:assigns])
  EEx.function_from_file(:def, :about, "lib/text_drop/views/home/about.html.eex", [:assigns])
end
