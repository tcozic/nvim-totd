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
│  [q] close   [e] edit   [m] mask   [<leader>sb] sandbox   [Y] yank        │
╰──────────────────────────────────────────────────────────────────────────╯
```

## Features

-  **Static Markdown Database** — Your custom tips live as files you own, version-control, and edit freely.
-  **Dynamic Virtual Tips** — Automatically parses `vimtutor` lessons and `:help tips` directly from Neovim's runtime without cluttering your hard drive.
-  **Custom External Sources** — Fetch tips from web APIs, GitHub, or company wikis on the fly using a simple Lua interface with persistent JSON disk caching.
-  **Anki-Lite Learning** — Tracks view counts. `:TotdRandom` automatically prioritizes unread or less-seen tips. Press `m` to **mask** a tip you've mastered so it stops appearing in random rolls.
-  **Context-Aware Rolls** — Automatically weights tips that match your current buffer's filetype.
-  **Interactive Sandbox** — Press `<leader>sb` to instantly open a tip's code block in a split window for safe practice, or press `Y` to yank it directly to your clipboard.
-  **Instant Materialization** — Press `e` on any virtual or web tip to instantly convert it into a physical `.md` file so you can add your own permanent notes.
-  **Native Fuzzy Finding** — Deep integration with both `Snacks.picker` and `Telescope` for searching your entire database (including virtual tips) with a custom Markdown previewer.

---

## Installation

### lazy.nvim (recommended)

```lua
{
  "you/nvim-totd",
  lazy = false,  -- or event = "VeryLazy" if show_on_startup = false
  opts = {
    db_path = vim.fn.stdpath("data") .. "/totd",  
    show_on_startup = false,
    
    -- Control which tip databases are loaded into the pool
    enabled_sources = { "local", "tutor", "help" },
    
    ui = {
      default_display = "float",  -- "float" | "split" | "scratch"
      border = "rounded",
      width  = 0.7,   
      height = 0.75,
      sandbox_split_direction = "vertical",
    },
    template = {
      default_mode       = "normal",
      default_complexity = "beginner",
      default_tags       = { "general" },
      default_source     = "User",
    },
  },
  keys = {
    { "<leader>tr", function() require("totd").random() end,  desc = "[T]ip [R]andom" },
    { "<leader>tc", function() require("totd").create() end,  desc = "[T]ip [C]reate" },
    { "<leader>tl", function() require("totd").last() end,    desc = "[T]ip [L]ast" },
    {
      -- Example using Snacks.picker (See Advanced Features for Telescope)
      "<leader>ts",
      function()
        -- ... Snacks picker configuration ...
      end,
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
| `q` / `<Esc>` | Close the tip|
| `e` | Edit the tip (Materializes virtual tips into local `.md` files)|
| `m` | Toggle Mask/Suspend (removes the tip from random rolls)|
| `<leader>sb` | Open the Practice Sandbox split|
| `Y` | Yank the sandbox code block to the unnamed and system clipboards (`"` and `+`) |
| `R` | Open Related tips menu (if defined in frontmatter)|

### Commands

| Command | Description |
|---------|-------------|
| `:TotdRandom` | Weighted random tip (prioritizes unread tips)|
| `:TotdRandom context=auto` | Random tip heavily weighted toward your current buffer's filetype |
| `:TotdRandom complexity=beginner` | Filtered random tip|
| `:TotdCreate [title]` | Scaffold a new tip|
| `:TotdOpen <identifier>` | Open a specific tip (tab-completes)|
| `:TotdList` | Print all tips to the message area|
| `:TotdEdit <identifier>` | Edit the raw Markdown file|
| `:TotdImport <path>` | Import an existing markdown file (supports globs)|
| `:TotdDelete <filename>` | Delete a physical tip|
| `:TotdLast` | Re-open the last viewed tip|
| `:TotdReset` | Reset all learning progress (view counts) to zero|
| `:TotdClearCache` | Clear persistent disk and memory caches for external web sources |
| `:TotdTeaser` | Print a compact dashboard teaser for a random tip|

---

##  Advanced Features

### Context-Aware Rolls
By passing `context=auto` to the randomizer, the plugin will check your current buffer's filetype (e.g., `lua`, `javascript`) and heavily boost the weight of tips that contain a matching tag. If no matches are found, it gracefully falls back to a standard random roll.

### Native Telescope Integration
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
## Author's Note
I originally conceived this plugin as a personal project to force myself to learn Neovim mechanics. I don't intend on becoming an experienced Lua dev, so the codebase was mostly generated using Gemini as an implementation assistant. 

If you are an experienced Lua developer and spot any non-idiomatic code, performance bottlenecks, or edge cases, **PRs and code reviews are incredibly welcome!** This project is as much a learning tool for me under the hood as it is for the users on the surface.
