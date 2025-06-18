local Client = require("verse.workflow_server.client")
local proto = require("verse.workflow_server.protocol")

local M = {}

local req_queue = {}

function M.connect()
  if M._client ~= nil and M._client:is_alive() then
    print("Already connected to Verse Workflow Server")
    return
  end

  local config = require("verse").get_config().workflow_server or {}
  local address = config.default_address or "127.0.0.1"
  local port = config.default_port or 1962

  req_queue = {}
  M._client = Client.connect_new(address, port, {
    on_connect = function()
      vim.notify("Connected to Verse Workflow Server",
        vim.log.levels.INFO, { title = "verse.nvim" })

      local reqs = req_queue
      req_queue = {}
      for _, req in ipairs(reqs) do
        M._process_request(req)
      end
    end,
    on_disconnect = function(err)
      if err ~= nil then
        vim.notify("Disconnected from Verse Workflow Server: " .. err,
          vim.log.levels.WARN, { title = "verse.nvim" })
      else
        vim.notify("Disconnected from Verse Workflow Server",
          vim.log.levels.INFO, { title = "verse.nvim" })
      end
    end,
  })
end

function M.disconnect()
  if M._client ~= nil then
    M._client:shutdown()
  end
end

--- @class verse.workflow_server.Request
---
--- Command name
--- @field cmd string
--- Optional command parameters
--- @field params? any
--- Callback when the request was actually sent
--- @field on_send? fun()

--- @param req verse.workflow_server.Request
function M._process_request(req)
  M._client:send_message(proto.MessageType.Request, req.cmd, req.params)
  if req.on_send ~= nil then
    vim.schedule(req.on_send)
  end
end

--- @param req verse.workflow_server.Request
local function send_request(req)
  if M._client == nil or not M._client:is_alive() then
    local auto_connect = require("verse").get_config().workflow_server.auto_connect
    if not auto_connect then
      vim.notify("Can't send request to Verse Workflow Server: client not connected",
        vim.log.levels.WARN, { title = "verse.nvim" })
    end

    M.connect()
  end
  if M._client.state == Client.ConnectionState.Connected then
    M._process_request(req)
  elseif M._client:is_alive() then
    table.insert(req_queue, req)
  end
end

--- Requests the server to build verse.
function M.build()
  send_request({
    cmd = "compileProject",
    on_send = function()
      print("Verse code build requested")
    end,
  })
end

--- @class verse.workflow_server.PushChangesOpts
---
--- Whether to only push Verse changes. If false, pushes all changes.
--- @field verse_only? boolean

--- Requests the server to push changes
--- @param opts? verse.workflow_server.PushChangesOpts
function M.push_changes(opts)
  opts = opts or {}
  local verse_only = true
  if type(opts.verse_only) == "boolean" then
    verse_only = opts.verse_only
  end
  send_request({
    cmd = "pushChanges",
    params = verse_only,
    on_send = function()
      if verse_only then
        print("Push Verse Changes requested")
      else
        print("Push Changes requested")
      end
    end,
  })
end

return M
