-- Hemingway-style background highlights for Vale diagnostics.

local M = {}

local ns = vim.api.nvim_create_namespace "vimingway"

-- Each kind of problem: its highlight group, its extmark priority, and
-- whether the color should cover the whole sentence. Word highlights sit
-- above sentence highlights, and red sits above yellow.
local kinds = {
  hard = { group = "VimingwayHard", priority = 150, sentence = true },
  very_hard = { group = "VimingwayVeryHard", priority = 151, sentence = true },
  complex = { group = "VimingwayComplex", priority = 160 },
  adverb = { group = "VimingwayAdverb", priority = 160 },
  passive = { group = "VimingwayPassive", priority = 160 },
}

local defaults = {
  enabled = false,
  notify = true,
  -- Diagnostic sources to read: vale-ls, and nvim-lint's Vale linter.
  sources = { "vale-ls", "vale" },
  -- Vale rule name -> kind. Set a rule to false to drop a default.
  rules = {
    ["Vimingway.HardSentence"] = "hard",
    ["Vimingway.VeryHardSentence"] = "very_hard",
    ["write-good.TooWordy"] = "complex",
    ["write-good.ThereIs"] = "complex",
    ["proselint.Needless"] = "complex",
    ["Voices.ColonReveal"] = "complex",
    ["Voices.ThroatClearing"] = "complex",
    ["write-good.Weasel"] = "adverb",
    ["proselint.Very"] = "adverb",
    ["write-good.Passive"] = "passive",
  },
  -- Background colors per 'background' value. Set to false to leave the
  -- Vimingway* highlight groups to your color scheme.
  palette = {
    light = {
      hard = "#f7ecb5",
      very_hard = "#e4b9b9",
      complex = "#dccde8",
      adverb = "#c4e3f3",
      passive = "#c4ed9d",
    },
    dark = {
      hard = "#4d4419",
      very_hard = "#5c2b2b",
      complex = "#43305c",
      adverb = "#1f3d57",
      passive = "#2d4a1f",
    },
  },
  -- Words ending in a period that don't end a sentence (lowercase).
  abbreviations = { "e.g.", "i.e.", "vs.", "cf.", "mr.", "mrs.", "ms.", "dr." },
}

local config
local enabled = false
local sources, abbreviations

local function set_highlights()
  if not config.palette then
    return
  end
  local colors = config.palette[vim.o.background] or config.palette.dark
  for kind, bg in pairs(colors) do
    if kinds[kind] then
      vim.api.nvim_set_hl(0, kinds[kind].group, { bg = bg })
    end
  end
end

local function to_set(list)
  local set = {}
  for _, v in ipairs(list) do
    set[v] = true
  end
  return set
end

-- Vale marks a long sentence by its first character only. Walk forward to
-- the sentence's closing punctuation, or the end of the paragraph.
local function sentence_end(buf, lnum, col)
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
  local from = col + 1
  while true do
    local s, e = line:find("[%.!?][\"')%]]*%f[%s%z]", from)
    if s then
      local word = line:sub(1, s):match "[%a%.]+$"
      if not (word and abbreviations[word:lower()]) then
        return lnum, e
      end
      from = e + 1
    else
      local next_line = lnum < last and vim.api.nvim_buf_get_lines(buf, lnum + 1, lnum + 2, false)[1] or ""
      if next_line:match "^%s*$" then
        return lnum, #line
      end
      lnum, from, line = lnum + 1, 1, next_line
    end
  end
end

local function render(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not enabled then
    return
  end
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local kind = sources[d.source] and kinds[config.rules[d.code] or ""]
    if kind then
      local end_lnum, end_col = d.end_lnum or d.lnum, d.end_col or d.col
      if kind.sentence then
        end_lnum, end_col = sentence_end(buf, d.lnum, d.col)
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, d.lnum, d.col, {
        end_row = end_lnum,
        end_col = end_col,
        hl_group = kind.group,
        priority = kind.priority,
        strict = false,
      })
    end
  end
end

local function render_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      render(buf)
    end
  end
end

local function set_enabled(value)
  if not config then
    M.setup()
  end
  enabled = value
  set_highlights()
  render_all()
  if config.notify then
    vim.notify("Vimingway " .. (enabled and "on" or "off"))
  end
end

function M.enable()
  set_enabled(true)
end

function M.disable()
  set_enabled(false)
end

function M.toggle()
  set_enabled(not enabled)
end

function M.is_enabled()
  return enabled
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})
  -- Lists replace the defaults rather than merging by index.
  if opts and opts.sources then
    config.sources = opts.sources
  end
  if opts and opts.abbreviations then
    config.abbreviations = opts.abbreviations
  end
  sources = to_set(config.sources)
  abbreviations = to_set(config.abbreviations)
  enabled = config.enabled

  set_highlights()

  local group = vim.api.nvim_create_augroup("Vimingway", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      if enabled and vim.api.nvim_buf_is_valid(args.buf) then
        render(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = set_highlights })

  render_all()
end

return M
