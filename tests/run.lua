-- Run with: nvim --headless -u NONE -l tests/run.lua
vim.opt.rtp:prepend "."
vim.cmd "runtime plugin/vimingway.lua"

local failures = 0
local function check(name, got, want)
  if not vim.deep_equal(got, want) then
    failures = failures + 1
    print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, vim.inspect(got), vim.inspect(want)))
  else
    print("ok   " .. name)
  end
end

local vimingway = require "vimingway"
vimingway.setup { notify = false }
local ns = vim.api.nvim_create_namespace "vimingway"
local diag_ns = vim.api.nvim_create_namespace "test-vale"

local function marks(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    table.insert(out, { d.hl_group, m[2], m[3], d.end_row, d.end_col })
  end
  table.sort(out, function(a, b)
    return a[2] * 1000 + a[3] < b[2] * 1000 + b[3]
  end)
  return out
end

local function buffer(lines, diags)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.diagnostic.set(diag_ns, buf, diags)
  return buf
end

local function diag(lnum, col, end_col, code, source)
  return { lnum = lnum, col = col, end_col = end_col, code = code, source = source or "vale-ls", message = code }
end

-- Off by default: nothing drawn.
local buf = buffer({ "It was written by me." }, { diag(0, 3, 14, "write-good.Passive") })
check("off by default", marks(buf), {})

vim.cmd "Vimingway on"
check("word highlight", marks(buf), { { "VimingwayPassive", 0, 3, 0, 14 } })

vim.cmd "Vimingway off"
check("off clears", marks(buf), {})
vim.cmd "Vimingway"
check("toggle back on", #marks(buf), 1)

-- Sentence across lines, ending at closing quote.
buf = buffer({ "One long sentence that", 'keeps going "here." Next one.' }, { diag(0, 0, 1, "Vimingway.HardSentence") })
check("sentence across lines", marks(buf), { { "VimingwayHard", 0, 0, 1, 19 } })

-- Abbreviations don't end the sentence.
buf = buffer({ "Use a tool, e.g. Vale, to check. Then more." }, { diag(0, 0, 1, "Vimingway.HardSentence") })
check("skips e.g.", marks(buf), { { "VimingwayHard", 0, 0, 0, 32 } })

-- No punctuation: stops at end of paragraph.
buf = buffer({ "no end here", "still going", "", "next para." }, { diag(0, 0, 1, "Vimingway.VeryHardSentence") })
check("paragraph end", marks(buf), { { "VimingwayVeryHard", 0, 0, 1, 11 } })

-- Last line without punctuation.
buf = buffer({ "trailing words" }, { diag(0, 0, 1, "Vimingway.HardSentence") })
check("end of buffer", marks(buf), { { "VimingwayHard", 0, 0, 0, 14 } })

-- nvim-lint source counts; other sources and unknown rules don't.
buf = buffer({ "very very" }, {
  diag(0, 0, 4, "proselint.Very", "vale"),
  diag(0, 5, 9, "proselint.Very", "other-linter"),
  diag(0, 5, 9, "Vale.Spelling"),
})
check("sources and rules", marks(buf), { { "VimingwayAdverb", 0, 0, 0, 4 } })

-- Priorities: words above sentences, red above yellow.
local prio = {}
buf = buffer({ "It was done." }, {
  diag(0, 0, 1, "Vimingway.HardSentence"),
  diag(0, 0, 1, "Vimingway.VeryHardSentence"),
  diag(0, 3, 11, "write-good.Passive"),
})
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  prio[m[4].hl_group] = m[4].priority
end
check("priorities", prio.VimingwayPassive > prio.VimingwayVeryHard and prio.VimingwayVeryHard > prio.VimingwayHard, true)

-- Options: extra rules, dropped defaults, palette by background.
vimingway.setup { enabled = true, notify = false, rules = { ["Blog.SentenceLength"] = "hard", ["write-good.Passive"] = false } }
buf = buffer({ "It was written. Long." }, {
  diag(0, 0, 1, "Blog.SentenceLength"),
  diag(0, 3, 14, "write-good.Passive"),
})
check("custom rules", marks(buf), { { "VimingwayHard", 0, 0, 0, 15 } })

vim.o.background = "light"
check("light palette", vim.api.nvim_get_hl(0, { name = "VimingwayHard" }).bg, 0xf7ecb5)
vim.o.background = "dark"
check("dark palette", vim.api.nvim_get_hl(0, { name = "VimingwayHard" }).bg, 0x4d4419)

-- Re-renders when diagnostics change.
buf = buffer({ "It was written." }, {})
check("no diagnostics", marks(buf), {})
vim.diagnostic.set(diag_ns, buf, { diag(0, 0, 1, "Vimingway.HardSentence") })
check("redraw on DiagnosticChanged", #marks(buf), 1)

print(failures == 0 and "all passed" or (failures .. " failed"))
vim.cmd(failures == 0 and "qa!" or "cq!")
