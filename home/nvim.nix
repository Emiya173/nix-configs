{ config, pkgs, lib, inputs, ... }:

{
  programs.nixvim = {
    enable = true;
    # flake.nix 里 inputs.nixvim.inputs.nixpkgs.follows = "nixpkgs",
    # nixvim 会因此告警"default 值被 follows 改了请显式确认",这里就是显式确认。
    nixpkgs.source = inputs.nixpkgs;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

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
          "<leader>/"  = "current_buffer_fuzzy_find";
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
      gitsigns.enable = true;
      lazygit.enable = true;

      # which-key 提示
      which-key = {
        enable = true;
        settings.preset = "modern";
      };

      # 注释 / 包围 / 配对 / 文本对象 (LazyVim 用 mini.*)
      mini = {
        enable = true;
        modules = {
          ai = {};
          surround = {};
          pairs = {};
          comment = {};
          icons = {};
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
        servers = {
          # Nix
          nil_ls.enable = true;
          nixd.enable = true;

          # Rust (注意: rust 项目里建议改用 rustaceanvim,这里给基础)
          rust_analyzer = {
            enable = true;
            installCargo = false;     # 由 rustup 提供
            installRustc = false;
          };

          # 前端
          ts_ls.enable = true;
          html.enable = true;
          cssls.enable = true;
          jsonls.enable = true;
          tailwindcss.enable = true;

          # Python
          pyright.enable = true;

          # Go
          gopls.enable = true;

          # Lua (写 nvim 配置时用)
          lua_ls.enable = true;

          # Bash
          bashls.enable = true;

          # Java / Kotlin / C/C++
          jdtls.enable = false;        # 项目时再开
          kotlin_language_server.enable = true;
          clangd.enable = true;

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
            "K"  = "hover";
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
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "buffer"; }
            { name = "path"; }
          ];
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>"     = "cmp.mapping.scroll_docs(-4)";
            "<C-f>"     = "cmp.mapping.scroll_docs(4)";
            "<CR>"      = "cmp.mapping.confirm({ select = true })";
            "<Tab>"     = "cmp.mapping(cmp.mapping.select_next_item(), {'i','s'})";
            "<S-Tab>"   = "cmp.mapping(cmp.mapping.select_prev_item(), {'i','s'})";
          };
        };
      };

      luasnip.enable = true;
      friendly-snippets.enable = true;

      # ----- 格式化 -----
      conform-nvim = {
        enable = true;
        settings = {
          format_on_save = {
            timeout_ms = 500;
            lsp_format = "fallback";
          };
          formatters_by_ft = {
            nix = [ "nixfmt" ];
            lua = [ "stylua" ];
            python = [ "ruff_format" "black" ];
            rust = [ "rustfmt" ];
            javascript = [ "prettierd" "prettier" ];
            typescript = [ "prettierd" "prettier" ];
            typescriptreact = [ "prettierd" "prettier" ];
            markdown = [ "prettierd" "prettier" ];
            yaml = [ "prettierd" "prettier" ];
            json = [ "prettierd" "prettier" ];
            sh = [ "shfmt" ];
            go = [ "gofmt" "goimports" ];
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

    # 来自 LazyVim 风格的核心键位 (which-key 会自动捡)
    keymaps = [
      { mode = "n"; key = "<leader>w"; action = "<cmd>w<cr>"; options.desc = "Save"; }
      { mode = "n"; key = "<leader>q"; action = "<cmd>q<cr>"; options.desc = "Quit"; }
      { mode = "n"; key = "<leader>e"; action = "<cmd>Neotree toggle<cr>"; options.desc = "Explorer"; }
      { mode = "n"; key = "<leader>gg"; action = "<cmd>LazyGit<cr>"; options.desc = "LazyGit"; }
      { mode = "n"; key = "<leader>xx"; action = "<cmd>Trouble diagnostics toggle<cr>"; options.desc = "Diagnostics"; }
      { mode = "n"; key = "<leader>bd"; action = "<cmd>bdelete<cr>"; options.desc = "Delete buffer"; }
      { mode = "n"; key = "<S-h>"; action = "<cmd>BufferLineCyclePrev<cr>"; options.desc = "Prev buffer"; }
      { mode = "n"; key = "<S-l>"; action = "<cmd>BufferLineCycleNext<cr>"; options.desc = "Next buffer"; }
      { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options.desc = "Window left"; }
      { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options.desc = "Window down"; }
      { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options.desc = "Window up"; }
      { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options.desc = "Window right"; }
      # 视觉模式上下移动行
      { mode = "v"; key = "J"; action = ":m '>+1<CR>gv=gv"; }
      { mode = "v"; key = "K"; action = ":m '<-2<CR>gv=gv"; }
      # ESC 取消高亮
      { mode = "n"; key = "<Esc>"; action = "<cmd>noh<cr><Esc>"; }
    ];

    # 把外部依赖的 CLI (formatter/linter) 一起进 PATH
    extraPackages = with pkgs; [
      nixfmt          # 即原 nixfmt-rfc-style,顶层 alias 已统一
      stylua
      shfmt
      shellcheck
      ruff
      black
      prettierd   # prettierd 已够,不再单独装 prettier
      markdownlint-cli
      gopls          # 让 gopls 自动可用 (nixvim 也会装,但保险)
    ];
  };
}
