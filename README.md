# nvim-totd · Tip of the Day

A data-driven Neovim plugin that surfaces **Vim tips as structured Markdown files**. It seamlessly blends your own custom tips with built-in Neovim documentation (`vimtutor` and `:help tips`), and uses an **Anki-lite spaced repetition** system to ensure you're always learning something new.

https://github.com/user-attachments/assets/e64deff5-3690-4075-ac81-10cca634304c

```text
╭──────────────────────────────────────────────────────────────────────────╮
│  mode: normal      complexity: beginner      tags: operators  efficiency  │
│  source: Practical Vim, Tip 6                [MASKED]                     │
│ ────────────────────────────────────────────────────────────────────────  │
│                                                                           │
│ # The Dot Formula                                                         │
│                                                                           │
│ **Commands:** `.` (repeat the last change)                                │
│                                                                           │
│ > **Synopsis:** The `.` command is the single most powerful feature in    │
│ > Vim — it lets you repeat any change with one keystroke.                 │
│                                                                           │
[1] hard   [2] good   [e] edit   [m] mask   [<leader>sb] sandbox   [q] close │
╰──────────────────────────────────────────────────────────────────────────╯
```

## Features

-  **Static Markdown Database** — Your custom tips live as files you own, version-control, and edit freely.
-  **Dynamic Virtual Tips** — Automatically parses `vimtutor` lessons and `:help tips` directly from Neovim's runtime without cluttering your hard drive.
-  **Custom External Sources** — Fetch tips from web APIs, GitHub, or company wikis on the fly using a simple Lua interface with persistent JSON disk caching.
-  **Active Spaced Repetition (Anki-Lite)** — Powered by an SM-2 "Gravity Pool" algorithm. Score tips as **Hard** or **Good** to schedule when they appear next. Overdue tips naturally rise to the top of random rolls.
-  **Context-Aware Rolls** — Automatically weights tips that match your current buffer's filetype.
-  **Interactive Sandbox** — Press `<leader>sb` to instantly open a tip's code block in a split window for safe practice, or press `Y` to yank it directly to your clipboard.
-  **Instant Materialization** — Press `e` on any virtual or web tip to instantly convert it into a physical `.md` file so you can add your own permanent notes.
-  **Native Fuzzy Finding** — Deep integration with both `Snacks.picker` and `Telescope` for searching your entire database. Masked/suspended tips are intelligently greyed out in the results.
-  **Seamless Integrations** — Integrations for `snacks.nvim` (Dashboard & Picker) and `lualine.nvim`.

## Requirements

- **Neovim >= 0.8.0** (Core functionality)
- **Neovim >= 0.9.4** (If using the recommended `Snacks.picker` integration)
- **Neovim >= 0.9.0** (If using the optional `Telescope` integration)
---

## Installation

### lazy.nvim (recommended)

```lua
{
  "tcozic/nvim-totd",
  lazy = false,  -- or event = "VeryLazy" if show_on_startup = false
  opts = {
    db_path = vim.fn.stdpath("data") .. "/totd",  
    show_on_startup = false,
    
    -- Control which tip databases are loaded into the pool
    enabled_sources = { "local", "tutor", "help" },
    
    ui = {
      default_display = "float",  
      border = "rounded",
      width  = 0.7,   
      height = 0.75,
      sandbox_split_direction = "vertical",
      
      -- What happens when you score (1/2) or mask (m) a tip?
      -- "close" | "reroll" | "open_next" | "keep_open"
      scoring_behavior = "reroll", 
    },
    template = {
      default_mode       = "normal",
      default_complexity = "beginner",
      default_tags       = { "general" },
      default_source     = "User",
    },
  },
    keys = {
    { 
      "<leader>tr", 
      function() 
        require("totd").pick_random() 
        vim.notify("[totd] Tip rerolled!", vim.log.levels.INFO)
      end,  
      desc = "[T]ip [R]oll" 
    },
    { 
      "<leader>te", 
      function() 
        local current = require("totd").get_current()
        if current then require("totd").open(current.path) end
      end,  
      desc = "[T]ip [E]xamine Current" 
    },
    { 
      "<leader>tc", 
      function() require("totd").create() end,  
      desc = "[T]ip [C]reate" 
    },
    {
      "<leader>ts",
      function() require("totd").snacks_picker() end,
      desc = "[T]ip [S]earch",
    },
  },
}
```

### Bootstrapping your database

Since `totd` is designed as a personal knowledge base, your physical database starts empty (though you will instantly see tips from the built-in `vimtutor` and `:help`). 

To create your very first physical tip, run:
`:TotdCreate "My First Tip"`

This will instantly scaffold a Markdown file in your `db_path` and open it for editing.

---

##  Usage

### Keymaps (Inside Tip Window)

| Keymap | Action |
|--------|--------|
| `1` | Score: **Hard** (Resets interval, you'll see it again tomorrow) |
| `2` | Score: **Good** (Increases interval, pushes it further into the future) |
| `m` | Toggle Mask/Suspend (Removes the tip from random rolls entirely) |
| `e` | Edit the tip (Materializes virtual tips into local `.md` files) |
| `q` / `<Esc>` | Close the tip |
| `<leader>sb` | Open the Practice Sandbox split |
| `Y` | Yank the sandbox code block to the unnamed and system clipboards (`"` and `+`) |
| `R` | Open Related tips menu (if defined in frontmatter) |
### Commands

| Command | Description |
|---------|-------------|
| `:TotdRandom` | Random tip (Headless rolls should use `require("totd").pick_random()` in Lua)|
| `:TotdRandom context=auto` | Random tip heavily weighted toward your current buffer's filetype |
| `:TotdRandom complexity=beginner` | Filtered random tip|
| `:TotdCreate [title]` | Scaffold a new tip|
| `:TotdOpen <identifier>` | Open a specific tip (tab-completes)|
| `:TotdList` | Print all tips to the message area|
| `:TotdEdit <identifier>` | Edit the raw Markdown file|
| `:TotdImport <path>` | Import an existing markdown file (supports globs)|
| `:TotdDelete <filename>` | Delete a physical tip|
| `:TotdLast` | Re-open the current/last viewed tip in memory|
| `:TotdReset` | Reset all learning progress (view counts) to zero|
| `:TotdClearCache` | Clear persistent disk and memory caches for external web sources |
| `:TotdTeaser` | Print a compact dashboard teaser for a random tip|

---

##  Advanced Features

### Context-Aware Rolls
By passing `context=auto` to the randomizer, the plugin will check your current buffer's filetype (e.g., `lua`, `javascript`) and heavily boost the weight of tips that contain a matching tag. If no matches are found, it gracefully falls back to a standard random roll.

### Native Telescope Integration
> **Author's Note:** *I personally use `Snacks.picker` for my daily workflow, so this Telescope extension is provided as-is and hasn't been heavily battle-tested. Bug reports and PRs from Telescope users are highly welcome!*
If you prefer `telescope.nvim` over `Snacks.picker`, `totd` provides a native extension complete with a specialized virtual-tip previewer. 

Add this to your configuration:
```lua
require("telescope").load_extension("totd")
```
Then run `:Telescope totd` to fuzzy-search your entire knowledge base.

### Custom Web/API Sources
You can fetch tips from external sources (like a company wiki or GitHub) by defining a custom source in your `opts`. Use the `auto_cache` parameter to permanently cache web responses to your disk (`"disk"`), cache them for the current session (`"session"`), or fetch them live every time (`"none"`).

```lua
opts = {
  enabled_sources = { "local", "tutor", "help", "company_wiki" },
  custom_sources = {
    company_wiki = {
      auto_cache = "disk", -- Writes to ~/.local/share/nvim/totd/.cache_source_company_wiki.json
      fetch = function()
        -- Return an array of parsed tips
        return {
          {
            fm = {
              title = "Deploying to Staging",
              mode = "bash",
              complexity = "intermediate",
              tags = {"devops"},
              source = "Internal Wiki",
            },
            body = "Run `./deploy.sh staging` from the root directory.\n\n```bash\n./deploy.sh staging\n```"
          }
        }
      end,
      -- Optional: custom logic to extract the sandbox code
      extract_sandbox = function(body)
        local code = body:match("```bash\n(.-)\n```")
        return code, "bash"
      end
    }
  }
}
```

### Dashboard Integration (Teasers)
Use `M.get_teaser_data(tip)` to pull a compact title and synopsis for display on startup screens (like `snacks.dashboard` or `alpha-nvim`).

```lua
local totd = require("totd")
local tip = totd.pick_random()
local teaser = totd.get_teaser_data(tip)

print(teaser.title)    -- e.g., "The Dot Formula"
print(teaser.synopsis) -- e.g., "The . command is the single most powerful feature..."
```

### Dashboard Integration example (as in demo)


```lua
sections = {
    { section = "header" },
    -- Drop this for default view
    require("totd").snacks_dashboard({ width = 50, action_key = " <leader>te" }),
    { section = "keys", gap = 1, padding = 1 },
```
### Lualine

For a minimalist approach, inject the current tip directly into your status bar. It's clickable! Clicking the tip in the statusline will instantly open the floating window to read it.
```lua
-- In your lualine.lua opts:
require('lualine').setup {
  sections = {
    lualine_c = {
      {'filename'},
      
      -- Drop this one-liner next to your filename
      require("totd").lualine_component({ icon = "", max_length = 40 })
    },
  }
}
```
---


## Tip Schema

Every physical `.md` file in `db_path` must include YAML frontmatter. (Virtual tips generate this on the fly).

```markdown
---
title: The Dot Formula
mode: normal
tags:
  - operators
  - efficiency
source: Practical Vim, Tip 6
complexity: beginner
related:
  - text-objects-grammar.md
---

# The Dot Formula

**Commands:** `.` (repeat the last change)

> **Synopsis:** One-sentence summary.

## Details
...

---
## Test it
Any standard fenced code block at the bottom of the file will be extracted when you open the Practice Sandbox!

\`\`\`vim
# Delete me!
\`\`\`
``` 
## 📝 Changelog

**Latest Major Updates:**
- **Active Spaced Repetition (SM-2):** Replaced passive view-count tracking with a fully functional Anki-lite "Gravity Pool" engine. Tips are now explicitly scored as "Hard" or "Good" to calculate their next due date.
- **Dynamic UI Workflows:** Added `opts.ui.scoring_behavior` to allow users to "binge" tips (`"open_next"`), silently refresh UI (`"reroll"`), or quickly dismiss (`"close"`) after scoring.
- **Masked Tip UI Polish:** The `Snacks.picker` integration now instantly greys out masked/suspended tips so you can see your active rotation at a glance.
- **Architectural Rewrite:** Decoupled the `api.lua` from the data layer (`progress.lua`) to eliminate race conditions and async file-saving bugs.
## Author's Note
I originally conceived this plugin as a personal project to force myself to learn Neovim mechanics. I don't intend on becoming an experienced Lua dev, so the codebase was mostly generated using Gemini as an implementation assistant. 

If you are an experienced Lua developer and spot any non-idiomatic code, performance bottlenecks, or edge cases, **PRs and code reviews are incredibly welcome!** This project is as much a learning tool for me under the hood as it is for the users on the surface.
