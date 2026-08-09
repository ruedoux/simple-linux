local M = {}

function M.setup()
  local augroup = vim.api.nvim_create_augroup("LspConfig", { clear = true })

  -- Diagnostic signs
  local diagnostic_signs = {
    Error = "\u{f057} ",
    Warn = "\u{f071} ",
    Hint = "\u{ea61}",
    Info = "\u{f05a}",
  }

  vim.diagnostic.config({
    virtual_text = { prefix = "\u{25cf}", spacing = 4 },
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = diagnostic_signs.Error,
        [vim.diagnostic.severity.WARN] = diagnostic_signs.Warn,
        [vim.diagnostic.severity.INFO] = diagnostic_signs.Info,
        [vim.diagnostic.severity.HINT] = diagnostic_signs.Hint,
      },
    },
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = {
      border = "rounded",
      source = true,
      header = "",
      prefix = "",
      focusable = false,
      style = "minimal",
    },
  })

  -- Rounded borders for floating LSP windows
  do
    local orig = vim.lsp.util.open_floating_preview
    function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
      opts = opts or {}
      opts.border = opts.border or "rounded"
      return orig(contents, syntax, opts, ...)
    end
  end

  -- LSP keymaps
  local function lsp_on_attach(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then return end

    local bufnr = ev.buf
    local opts = { noremap = true, silent = true, buffer = bufnr }

    vim.keymap.set("n", "<leader>gd", function()
      require("fzf-lua").lsp_definitions({ jump1 = true })
    end, opts)

    vim.keymap.set("n", "<leader>gD", vim.lsp.buf.definition, opts)

    vim.keymap.set("n", "<leader>gS", function()
      vim.cmd("vsplit")
      vim.lsp.buf.definition()
    end, opts)

    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

    vim.keymap.set("n", "<leader>D", function()
      vim.diagnostic.open_float({ scope = "line" })
    end, opts)
    vim.keymap.set("n", "<leader>d", function()
      vim.diagnostic.open_float({ scope = "cursor" })
    end, opts)
    vim.keymap.set("n", "<leader>nd", function()
      vim.diagnostic.jump({ count = 1 })
    end, opts)
    vim.keymap.set("n", "<leader>pd", function()
      vim.diagnostic.jump({ count = -1 })
    end, opts)

    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)

    vim.keymap.set("n", "<leader>fr", function()
      require("fzf-lua").lsp_references()
    end, opts)
    vim.keymap.set("n", "<leader>ft", function()
      require("fzf-lua").lsp_typedefs()
    end, opts)
    vim.keymap.set("n", "<leader>fs", function()
      require("fzf-lua").lsp_document_symbols()
    end, opts)
    vim.keymap.set("n", "<leader>fw", function()
      require("fzf-lua").lsp_workspace_symbols()
    end, opts)
    vim.keymap.set("n", "<leader>fi", function()
      require("fzf-lua").lsp_implementations()
    end, opts)

    if client:supports_method("textDocument/codeAction", bufnr) then
      vim.keymap.set("n", "<leader>oi", function()
        vim.lsp.buf.code_action({
          context = { only = { "source.organizeImports" }, diagnostics = {} },
          apply = true,
          bufnr = bufnr,
        })
        vim.defer_fn(function()
          vim.lsp.buf.format({ bufnr = bufnr })
        end, 50)
      end, opts)
    end
  end

  vim.api.nvim_create_autocmd("LspAttach", { group = augroup, callback = lsp_on_attach })

  vim.keymap.set("n", "<leader>q", function()
    vim.diagnostic.setloclist({ open = true })
  end, { desc = "Open diagnostic list" })
  vim.keymap.set("n", "<leader>dl", vim.diagnostic.open_float, { desc = "Show line diagnostics" })

  -- Completion
  require("blink.cmp").setup({
    keymap = {
      preset = "none",
      ["<C-Space>"] = { "show", "hide" },
      ["<CR>"] = { "accept", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
      ["<Tab>"] = { "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
    },
    appearance = { nerd_font_variant = "mono" },
    completion = {
      menu = {
        auto_show = function()
          return vim.bo.filetype ~= "markdown"
        end,
      },
    },
    sources = { default = { "lsp", "path", "buffer", "snippets" } },
    snippets = {
      expand = function(snippet)
        require("luasnip").lsp_expand(snippet)
      end,
    },
    fuzzy = {
      implementation = "prefer_rust",
      prebuilt_binaries = { download = true },
    },
  })

  -- LSP server capabilities
  vim.lsp.config["*"] = {
    capabilities = require("blink.cmp").get_lsp_capabilities(),
  }

  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        telemetry = { enable = false },
      },
    },
  })
  vim.lsp.config("basedpyright", {})
  vim.lsp.config("clangd", {})
  vim.lsp.config("roslyn_ls", {
    capabilities = {
      textDocument = {
        diagnostic = {
          dynamicRegistration = true,
        },
      },
    },
    settings = {
      ["csharp|background_analysis"] = {
        dotnet_analyzer_diagnostics_scope = "fullSolution",
        dotnet_compiler_diagnostics_scope = "fullSolution",
      },
      ["csharp|completion"] = {
        dotnet_show_name_completion_suggestions = true,
        dotnet_show_completion_items_from_unimported_namespaces = true,
        dotnet_provide_regex_completions = true,
      },
      ["csharp|inlay_hints"] = {
        csharp_enable_inlay_hints_for_implicit_object_creation = true,
        csharp_enable_inlay_hints_for_implicit_variable_types = true,
        csharp_enable_inlay_hints_for_lambda_parameter_types = true,
        csharp_enable_inlay_hints_for_types = true,
        dotnet_enable_inlay_hints_for_parameters = true,
      },
      ["csharp|code_lens"] = {
        dotnet_enable_references_code_lens = true,
      },
    },
  })

  vim.g.rustaceanvim = {
    server = {
      capabilities = require("blink.cmp").get_lsp_capabilities(),
    },
  }

  vim.lsp.enable({ "lua_ls", "basedpyright", "clangd", "roslyn_ls" })

  -- Auto-install LSP servers via Mason
  require("mason").setup({})

  vim.api.nvim_create_autocmd("User", {
    pattern = "MasonUpdateCompleted",
    callback = function()
      local registry = require("mason-registry")
      local servers = { "lua-language-server", "basedpyright", "clangd", "roslyn-language-server" }
      for _, srv in ipairs(servers) do
        local ok, pkg = pcall(registry.get_package, srv)
        if not ok then
          vim.notify("Mason: failed to look up package '" .. srv .. "'", vim.log.levels.WARN)
        elseif pkg and not pkg:is_installed() then
          vim.notify("Mason: installing " .. srv .. " ...", vim.log.levels.INFO)
          local install_ok, err = pcall(pkg.install, pkg)
          if not install_ok then
            vim.notify("Mason: failed to install " .. srv .. ": " .. tostring(err), vim.log.levels.WARN)
          end
        elseif not pkg then
          vim.notify("Mason: package '" .. srv .. "' not found in registry", vim.log.levels.WARN)
        end
      end
    end,
  })
end

return M
