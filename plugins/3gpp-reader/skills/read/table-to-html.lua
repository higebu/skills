-- Pandoc Lua filter: preserve tables as raw HTML to retain colspan/rowspan
function Table(el)
  return pandoc.RawBlock("markdown", pandoc.write(pandoc.Pandoc({el}), "html"))
end
