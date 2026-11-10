local M = {}

local FORMATTER = [[
import json
import sys

INDENT = 2
MAX_WIDTH = 100


def scalar(v):
    return v is None or isinstance(v, (str, int, float, bool))


def dumps_scalar(v):
    return json.dumps(v, ensure_ascii=False)


def fmt(v, level):
    pad = " " * (level * INDENT)
    inner_pad = " " * ((level + 1) * INDENT)

    if scalar(v):
        return dumps_scalar(v)

    if isinstance(v, list):
        if not v:
            return "[]"
        if all(scalar(x) for x in v):
            inline = "[" + ", ".join(dumps_scalar(x) for x in v) + "]"
            if len(pad) + len(inline) <= MAX_WIDTH:
                return inline
        parts = [inner_pad + fmt(x, level + 1) for x in v]
        return "[\n" + ",\n".join(parts) + "\n" + pad + "]"

    if isinstance(v, dict):
        if not v:
            return "{}"
        if all(scalar(x) for x in v.values()):
            items = [dumps_scalar(k) + ": " + dumps_scalar(val) for k, val in v.items()]
            inline = "{" + ", ".join(items) + "}"
            if len(pad) + len(inline) <= MAX_WIDTH:
                return inline
        parts = []
        for k, val in v.items():
            parts.append(inner_pad + dumps_scalar(k) + ": " + fmt(val, level + 1))
        return "{\n" + ",\n".join(parts) + "\n" + pad + "}"

    return dumps_scalar(v)


def main():
    try:
        obj = json.loads(sys.stdin.read())
    except json.JSONDecodeError as e:
        sys.stderr.write("json: " + str(e) + "\n")
        sys.exit(1)
    print(fmt(obj, 0))


if __name__ == "__main__":
    main()
]]

function M.format_json()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")

  local obj = vim.system({ "python3", "-c", FORMATTER }, { stdin = input, text = true }):wait()

  if obj.code == 0 then
    local out = vim.split(obj.stdout, "\n", { plain = true })
    if out[#out] == "" then
      table.remove(out)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  else
    vim.notify("json-format: " .. (obj.stderr or "format failed"), vim.log.levels.ERROR)
  end
end

return M
