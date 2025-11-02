local M = {}

--- Injects a path transformer into outgoing LSP requests.
--- @param client vim.lsp.Client
function M.inject_nil_suppression(client)
  if client["nil_suppression_injected"] then
    return
  end
  client["nil_suppression_injected"] = true

  local orig_fn_request = client.request
  client.request = function(_client, _method, _params, handler, ...)
    if type(handler) == "function" then
      handler = M._wrap_request_handler(handler)
    end
    return orig_fn_request(_client, _method, _params, handler, ...)
  end
end

--- @param orig_handler lsp.Handler
--- @return lsp.Handler
function M._wrap_request_handler(orig_handler)
  return function(_err, result, ...)
    if type(result) == "table" then
      M._deep_suppress_nil(result)
    end
    return orig_handler(_err, result, ...)
  end
end

--- @param result table
function M._deep_suppress_nil(result)
  local stack = { result }
  while #stack > 0 do
    local current = table.remove(stack)
    for key, value in pairs(current) do
      if value == vim.NIL then
        current[key] = nil
      elseif type(value) == "table" then
        table.insert(stack, value)
      end
    end
  end
end

return M
