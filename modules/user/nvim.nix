{
  pkgs,
  inputs,
  ...
}:

let
  # 精确文件名和自定义模式先于 Snacks 的通用规则匹配，也需要检查大小。
  logFiletype.__raw = ''
    function(path, buf)
      if vim.bo[buf].filetype ~= "bigfile"
        and vim.fn.getfsize(path) > Snacks.config.bigfile.size then
        return "bigfile"
      end
      return "log"
    end
  '';
in
{
  imports = [ inputs.nixvim.nixosModules.nixvim ];

  programs.nixvim = {
    enable = true;
    # flake.nix 里 inputs.nixvim.inputs.nixpkgs.follows = "nixpkgs",
    # nixvim 会因此告警"default 值被 follows 改了请显式确认",这里就是显式确认。
    nixpkgs.source = inputs.nixpkgs;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    wrapRc = true;
    # Keep user runtime additions (e.g. after/) available, as in the HM module.
    impureRtp = true;

    # ----- 基础 vim 选项 (对齐 LazyVim 默认值) -----
    globals.mapleader = " ";
    globals.maplocalleader = "\\";

    opts = {
      number = true;
      relativenumber = true;
      mouse = "a";
      clipboard = "unnamedplus";
      signcolumn = "yes";
      cursorline = true;
      termguicolors = true;
      undofile = true;
      undolevels = 10000;
      ignorecase = true;
      smartcase = true;
      smartindent = true;
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
      softtabstop = 2;
      scrolloff = 4;
      sidescrolloff = 8;
      splitright = true;
      splitbelow = true;
      wrap = false;
      timeoutlen = 300;
      updatetime = 200;
      pumheight = 10;
      pumblend = 10;
      winblend = 10;
      conceallevel = 2;
      laststatus = 3;
      list = true;
      confirm = true;
    };

    # 使用 Neovim 内置的 log 语法，补全通用日志和轮转文件的识别。
    filetype = {
      extension.log = logFiletype;
      filename = {
        syslog = logFiletype;
        messages = logFiletype;
      };
      pattern = {
        ".*%.log%.%d+" = logFiletype;
        ".*%.log%-%d[%d%-]*" = logFiletype;
        ".*_log" = logFiletype;
      };
    };

    # ----- 主题 -----
    colorschemes.tokyonight = {
      enable = true;
      settings = {
        style = "moon";
        transparent = false;
        styles.sidebars = "transparent";
      };
    };

    # ----- 插件 (LazyVim 子集) -----
    plugins = {
      # 文件树
      neo-tree = {
        enable = true;
        settings = {
          close_if_last_window = true;
          filesystem.follow_current_file.enabled = true;
        };
      };

      # 模糊查找
      telescope = {
        enable = true;
        extensions.fzf-native.enable = true;
        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fr" = "oldfiles";
          "<leader>/" = "current_buffer_fuzzy_find";
          "<leader>ss" = {
            action = "lsp_document_symbols";
            options.desc = "Document symbols";
          };
          "<leader>sS" = {
            action = "lsp_dynamic_workspace_symbols";
            options.desc = "Workspace symbols";
          };
          "<leader>sw" = {
            action = "grep_string";
            options.desc = "Search word";
          };
          "<leader>sk" = {
            action = "keymaps";
            options.desc = "Search keymaps";
          };
        };
      };

      grug-far.enable = true;

      snacks = {
        enable = true;
        settings = {
          bigfile = {
            enabled = true;
            size = 1536 * 1024;
          };
          terminal = {
            enabled = true;
            win = {
              position = "float";
              border = "rounded";
            };
          };
        };
      };

      # 状态栏
      lualine = {
        enable = true;
        settings.options.theme = "tokyonight";
      };

      # buffer 标签
      bufferline.enable = true;

      # tree-sitter 高亮 / 缩进 / 文本对象
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };
      treesitter-textobjects.enable = true;
      treesitter-context.enable = true;

      # Git 增量提示 + lazygit
      gitsigns = {
        enable = true;
        settings = {
          current_line_blame = false;
          current_line_blame_opts = {
            delay = 0;
            virt_text_pos = "eol";
          };
          on_attach.__raw = ''
            function(bufnr)
              if vim.bo[bufnr].filetype == "bigfile" then
                return false
              end
              local gs = require("gitsigns")
              local function map(mode, key, action, desc)
                vim.keymap.set(mode, key, action, { buffer = bufnr, silent = true, desc = desc })
              end
              map("n", "]h", function()
                if vim.wo.diff then
                  vim.cmd.normal({ "]c", bang = true })
                else
                  gs.nav_hunk("next")
                end
              end, "Next hunk")
              map("n", "[h", function()
                if vim.wo.diff then
                  vim.cmd.normal({ "[c", bang = true })
                else
                  gs.nav_hunk("prev")
                end
              end, "Previous hunk")
              map("n", "<leader>ghp", gs.preview_hunk, "Preview hunk")
              map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<cr>", "Stage hunk")
              map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<cr>", "Reset hunk")
            end
          '';
        };
      };
      lazygit.enable = true;

      # 按需在默认浏览器中实时预览 Markdown。
      markdown-preview = {
        enable = true;
        settings = {
          auto_start = 0;
          open_to_the_world = 0;
        };
      };

      # which-key 提示
      which-key = {
        enable = true;
        settings = {
          preset = "modern";
          # 分组名称无法从各快捷键的 desc 自动推导。
          spec = [
            {
              __unkeyed-1 = "<leader>b";
              group = "Buffers";
              icon = "󰈔";
            }
            {
              __unkeyed-1 = "<leader>c";
              group = "Code";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>f";
              group = "Files / Search";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>g";
              group = "Git";
              icon = "󰊢";
            }
            {
              __unkeyed-1 = "<leader>gh";
              group = "Hunks";
              icon = "󰊢";
            }
            {
              __unkeyed-1 = "<leader>m";
              group = "Markdown";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>q";
              group = "Quit / Session";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>s";
              group = "Search";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>u";
              group = "UI / Toggles";
              icon = "";
            }
            {
              __unkeyed-1 = "<leader>x";
              group = "Diagnostics";
              icon = "󱖫";
            }
            {
              __unkeyed-1 = "gs";
              group = "Surround";
              icon = "󰅪";
            }
          ];
        };
      };

      # 注释 / 包围 / 配对 / 文本对象 (LazyVim 用 mini.*)
      mini = {
        enable = true;
        modules = {
          ai = { };
          surround.mappings = {
            add = "gsa";
            delete = "gsd";
            find = "gsf";
            find_left = "gsF";
            highlight = "gsh";
            replace = "gsr";
          };
          pairs = { };
          comment = { };
          icons = { };
        };
      };

      # 跳转
      flash.enable = true;

      # TODO/FIXME 高亮
      todo-comments.enable = true;

      # 错误/诊断面板
      trouble.enable = true;

      # 缩进线
      indent-blankline.enable = true;

      # 通知
      noice.enable = true;
      notify.enable = true;

      # 自动 session
      persistence.enable = true;

      # web-devicons (供 neo-tree/lualine/bufferline 用)
      web-devicons.enable = true;

      # ----- LSP -----
      lsp = {
        enable = true;
        # LspAttach 时对支持的 server 开 vim.lsp.inlay_hint
        # (rust_analyzer/clangd/hls/ts_ls/ty 均支持)
        inlayHints = true;
        servers = {
          # Nix
          nil_ls.enable = true;
          nixd.enable = true;

          # Rust (注意: rust 项目里建议改用 rustaceanvim,这里给基础)
          rust_analyzer = {
            enable = true;
            installCargo = false; # 由 rustup 提供
            installRustc = false;
          };

          # 前端
          ts_ls.enable = true;
          html.enable = true;
          cssls.enable = true;
          jsonls.enable = true;
          tailwindcss.enable = true;

          # Python: ruff 管 lint/格式化/import 整理,ty (Astral) 管类型检查/补全
          ruff.enable = true;
          ty.enable = true;

          # Go
          gopls.enable = true;

          # Lua (写 nvim 配置时用)
          lua_ls.enable = true;

          # Bash
          bashls.enable = true;

          # Java / Kotlin / C/C++
          jdtls.enable = false; # 项目时再开
          kotlin_language_server.enable = true;
          clangd.enable = true;

          # Haskell (GHC 已在 dev.nix 安装到用户环境,不让 nixvim 再拖一份)
          hls = {
            enable = true;
            installGhc = false;
          };

          # YAML / TOML / Markdown
          yamlls.enable = true;
          taplo.enable = true;
          marksman.enable = true;
        };
        keymaps = {
          lspBuf = {
            "gd" = "definition";
            "gr" = "references";
            "gI" = "implementation";
            "gy" = "type_definition";
            "K" = "hover";
            "<leader>cr" = "rename";
            "<leader>ca" = "code_action";
            "<leader>cf" = "format";
          };
          diagnostic = {
            "[d" = "goto_prev";
            "]d" = "goto_next";
            "<leader>cd" = "open_float";
          };
        };
      };

      # ----- 自动补全 -----
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          enabled.__raw = ''
            function()
              return vim.b.completion ~= false
                and vim.bo.buftype ~= "prompt"
                and vim.fn.reg_recording() == ""
                and vim.fn.reg_executing() == ""
            end
          '';
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "buffer"; }
            { name = "path"; }
          ];
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i','s'})";
            "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i','s'})";
          };
        };
      };

      luasnip.enable = true;
      friendly-snippets.enable = true;

      # ----- 格式化 -----
      conform-nvim = {
        enable = true;
        settings = {
          format_on_save.__raw = ''
            function(bufnr)
              if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat
                or vim.bo[bufnr].filetype == "bigfile" then
                return
              end
              return { timeout_ms = 500, lsp_format = "fallback" }
            end
          '';
          formatters_by_ft = {
            nix = [ "nixfmt" ];
            lua = [ "stylua" ];
            python = [
              "ruff_format"
              "black"
            ];
            rust = [ "rustfmt" ];
            javascript = [
              "prettierd"
              "prettier"
            ];
            typescript = [
              "prettierd"
              "prettier"
            ];
            typescriptreact = [
              "prettierd"
              "prettier"
            ];
            markdown = [
              "prettierd"
              "prettier"
            ];
            yaml = [
              "prettierd"
              "prettier"
            ];
            json = [
              "prettierd"
              "prettier"
            ];
            sh = [ "shfmt" ];
            go = [
              "gofmt"
              "goimports"
            ];
          };
        };
      };

      # ----- Linting -----
      lint = {
        enable = true;
        lintersByFt = {
          nix = [ "nix" ];
          markdown = [ "markdownlint" ];
          sh = [ "shellcheck" ];
        };
      };
    };

    extraConfigLuaPost = ''
      Snacks.toggle({
        name = "Autoformat (global)",
        get = function() return not vim.g.disable_autoformat end,
        set = function(state) vim.g.disable_autoformat = not state end,
      }):map("<leader>uf")
      Snacks.toggle({
        name = "Autoformat (buffer)",
        get = function() return not vim.b.disable_autoformat end,
        set = function(state) vim.b.disable_autoformat = not state end,
      }):map("<leader>uF")
      Snacks.toggle.inlay_hints():map("<leader>uh")
      Snacks.toggle.diagnostics():map("<leader>ud")
      Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
    '';

    # 来自 LazyVim 风格的核心键位 (which-key 会自动捡)
    keymaps = [
      {
        mode = "n";
        key = "<leader>w";
        action = "<cmd>w<cr>";
        options.desc = "Save";
      }
      {
        mode = "n";
        key = "<leader>qq";
        action = "<cmd>q<cr>";
        options.desc = "Quit";
      }
      {
        mode = "n";
        key = "<leader>qs";
        action.__raw = "function() require('persistence').load() end";
        options.desc = "Restore session";
      }
      {
        mode = "n";
        key = "<leader>qS";
        action.__raw = "function() require('persistence').select() end";
        options.desc = "Select session";
      }
      {
        mode = "n";
        key = "<leader>ql";
        action.__raw = "function() require('persistence').load({ last = true }) end";
        options.desc = "Restore last session";
      }
      {
        mode = "n";
        key = "<leader>qd";
        action.__raw = "function() require('persistence').stop() end";
        options.desc = "Stop saving session";
      }
      {
        mode = "n";
        key = "<leader>e";
        action = "<cmd>Neotree toggle<cr>";
        options.desc = "Explorer";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "s";
        action.__raw = "function() require('flash').jump() end";
        options.desc = "Flash jump";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "S";
        action.__raw = "function() require('flash').treesitter() end";
        options.desc = "Flash Treesitter";
      }
      {
        mode = [
          "n"
          "x"
        ];
        key = "<leader>sr";
        action = ":GrugFar<cr>";
        options.desc = "Search and replace";
      }
      {
        mode = "n";
        key = "<leader>ft";
        action.__raw = "function() Snacks.terminal.toggle() end";
        options.desc = "Toggle terminal";
      }
      {
        mode = [
          "n"
          "t"
        ];
        key = "<C-/>";
        action.__raw = "function() Snacks.terminal.toggle() end";
        options.desc = "Toggle terminal";
      }
      {
        mode = [
          "n"
          "t"
        ];
        key = "<C-_>";
        action.__raw = "function() Snacks.terminal.toggle() end";
        options.desc = "Toggle terminal";
      }
      {
        mode = "n";
        key = "<leader>gg";
        action = "<cmd>LazyGit<cr>";
        options.desc = "LazyGit";
      }
      {
        mode = "n";
        key = "<leader>gb";
        action = "<cmd>Gitsigns toggle_current_line_blame<cr>";
        options.desc = "Toggle inline Git blame";
      }
      {
        mode = "n";
        key = "<leader>gB";
        action = "<cmd>Gitsigns blame<cr>";
        options.desc = "Git blame file";
      }
      {
        mode = "n";
        key = "<leader>gi";
        action = "<cmd>Gitsigns blame_line full=true<cr>";
        options.desc = "Git blame line";
      }
      {
        mode = "n";
        key = "<leader>mp";
        action = "<cmd>MarkdownPreviewToggle<cr>";
        options.desc = "Markdown preview";
      }
      {
        mode = "n";
        key = "<leader>xx";
        action = "<cmd>Trouble diagnostics toggle<cr>";
        options.desc = "Diagnostics";
      }
      {
        mode = "n";
        key = "<leader>xX";
        action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
        options.desc = "Buffer diagnostics";
      }
      {
        mode = "n";
        key = "<leader>xq";
        action = "<cmd>Trouble qflist toggle<cr>";
        options.desc = "Quickfix list";
      }
      {
        mode = "n";
        key = "<leader>xl";
        action = "<cmd>Trouble loclist toggle<cr>";
        options.desc = "Location list";
      }
      {
        mode = "n";
        key = "[t";
        action.__raw = "function() require('todo-comments').jump_prev() end";
        options.desc = "Previous TODO";
      }
      {
        mode = "n";
        key = "]t";
        action.__raw = "function() require('todo-comments').jump_next() end";
        options.desc = "Next TODO";
      }
      {
        mode = "n";
        key = "<leader>st";
        action = "<cmd>TodoTelescope<cr>";
        options.desc = "Search TODOs";
      }
      {
        mode = "n";
        key = "<leader>bd";
        action = "<cmd>bdelete<cr>";
        options.desc = "Delete buffer";
      }
      {
        mode = "n";
        key = "<S-h>";
        action = "<cmd>BufferLineCyclePrev<cr>";
        options.desc = "Prev buffer";
      }
      {
        mode = "n";
        key = "<S-l>";
        action = "<cmd>BufferLineCycleNext<cr>";
        options.desc = "Next buffer";
      }
      {
        mode = "n";
        key = "<C-h>";
        action = "<C-w>h";
        options.desc = "Window left";
      }
      {
        mode = "n";
        key = "<C-j>";
        action = "<C-w>j";
        options.desc = "Window down";
      }
      {
        mode = "n";
        key = "<C-k>";
        action = "<C-w>k";
        options.desc = "Window up";
      }
      {
        mode = "n";
        key = "<C-l>";
        action = "<C-w>l";
        options.desc = "Window right";
      }
      # 视觉模式上下移动行
      {
        mode = "v";
        key = "J";
        action = ":m '>+1<CR>gv=gv";
      }
      {
        mode = "v";
        key = "K";
        action = ":m '<-2<CR>gv=gv";
      }
      # ESC 取消高亮
      {
        mode = "n";
        key = "<Esc>";
        action = "<cmd>noh<cr><Esc>";
      }
    ];

    # 把外部依赖的 CLI (formatter/linter) 一起进 PATH
    extraPackages = with pkgs; [
      ripgrep
      nixfmt # 即原 nixfmt-rfc-style,顶层 alias 已统一
      stylua
      shfmt
      shellcheck
      ruff
      black
      prettierd # prettierd 已够,不再单独装 prettier
      markdownlint-cli
      gopls # 让 gopls 自动可用 (nixvim 也会装,但保险)
    ];
  };
}
