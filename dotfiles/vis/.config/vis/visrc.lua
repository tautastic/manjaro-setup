require('vis')

vis.events.subscribe(vis.events.WIN_OPEN, function(win)
  vis:command("set theme 'base16-default-dark'")
end)


vis.events.subscribe(vis.events.INIT, function()
  vis.options.autoindent = true
vis.options.escdelay = 50
vis.options.ignorecase = false

  
vis:map(vis.modes.NORMAL, '  w', ':set showtabs!<Enter>:set showspaces!<Enter>')





  vis:command("set syntax auto")
vis:command("set theme base16-default-dark")

local hidden_all = false

local function toggle_hidden_all()
  hidden_all = not hidden_all

  if hidden_all then
    vis:command("set statusbar off")
  else
    vis:command("set statusbar on")
  end

  vis:redraw()
end

vis:map(
  vis.modes.NORMAL,
  " h",
  toggle_hidden_all
)

local function quote_word(quote)
  local win = vis.win
  local file = win.file
  local pos = win.selection.pos
  local range = file:text_object_longword(pos)

  if not range then
    return
  end

  local text = file:content(range)
  local replacement = quote .. text .. quote

  file:delete(range)
  file:insert(range.start, replacement)

  win.selection.pos = range.start + #replacement - 1
end

local function remove_quotes()
  local win = vis.win
  local file = win.file
  local pos = win.selection.pos
  local range = file:text_object_longword(pos)

  if not range then
    return
  end

  local text = file:content(range)
  local replacement = text:gsub("['\"]", "")

  file:delete(range)
  file:insert(range.start, replacement)

  if #replacement > 0 then
    win.selection.pos = range.start + #replacement - 1
  else
    win.selection.pos = range.start
  end
end

vis:map(
  vis.modes.NORMAL,
  " dq",
  function()
    quote_word('"')
  end
)

vis:map(
  vis.modes.NORMAL,
  " sq",
  function()
    quote_word("'")
  end
)

vis:map(
  vis.modes.NORMAL,
  " rq",
  remove_quotes
)

vis.events.subscribe(
  vis.events.FILE_SAVE_PRE,
  function(file, path)
    local text = file:content(0, file.size)

    text = text:gsub("[ \t]+\n", "\n")
    text = text:gsub("[ \t]+$", "")
    text = text:gsub("\n+$", "")

    if path and path:match("%.[ch]$") then
      text = text .. "\n"
    end

    file:delete(0, file.size)
    file:insert(0, text)

    return true
  end
)

vis:command_register(
  "ToSpaces",
  function()
    local win = vis.win
    local tabwidth = win.options.tabwidth

    vis:command("set expandtab")
    vis:command("retab!")

    win.options.tabwidth = tabwidth

    vis:info(
      "Converted to spaces (tabwidth = " .. tabwidth .. ")"
    )

    return true
  end,
  "Convert tabs to spaces"
)

vis:command_register(
  "ToTabs",
  function()
    local win = vis.win
    local tabwidth = win.options.tabwidth

    vis:command("set expandtab")
    vis:command("retab!")
    vis:command("set noexpandtab")
    vis:command("retab!")

    win.options.tabwidth = tabwidth

    vis:info(
      "Converted to tabs (tabwidth = " .. tabwidth .. ")"
    )

    return true
  end,
  "Convert spaces to tabs"
)

end)

vis.events.subscribe(vis.events.WIN_OPEN, function(win)
  win.options.cursorline = true
win.options.expandtab = true
win.options.numbers = true
win.options.relativenumbers = true
win.options.showeof = true
win.options.showspaces = true
win.options.showtabs = true
win.options.statusbar = true
win.options.tabwidth = 2
win.options.wrapcolumn = 0
end)
