---@class verse.workflow_server.Client
---@field state integer
---@field seq integer
---@field socket uv.uv_tcp_t
---@field opts verse.workflow_server.ClientOpts
local Client = {}
Client.__index = Client

Client.ConnectionState = {
  Connecting = 0,
  Connected = 1,
  Disconnected = 2,
  Failed = 3,
}

--- @class verse.workflow_server.ClientOpts
--- @field on_connect? fun() Post connect callback
--- @field on_disconnect? fun(err?:string) Post disconnect callback

--- @param address string
--- @param port integer
--- @param opts? verse.workflow_server.ClientOpts
function Client.connect_new(address, port, opts)
  --- @type verse.workflow_server.Client
  local self = setmetatable({}, Client)
  self.seq = 1
  self.opts = opts or {}

  local socket = vim.uv.new_tcp()
  if socket == nil then
    self.state = Client.ConnectionState.Failed
    return
  end
  self.socket = socket
  self.state = Client.ConnectionState.Connecting
  socket:connect(address, port, function(err)
    if err == nil then
      self.state = Client.ConnectionState.Connected
      if self.opts.on_connect ~= nil then
        vim.schedule(self.opts.on_connect)
      end
    else
      self.state = Client.ConnectionState.Failed
      vim.schedule(function()
        vim.notify("Connection to Verse Workflow Server at " .. address .. ":" .. port .. " failed: " .. err,
          vim.log.levels.WARN, { title = "verse.nvim" })
      end)
    end
  end)

  return self
end

--- @return boolean # Whether the client is alive
function Client:is_alive()
  return self.state == Client.ConnectionState.Connected or
    self.state == Client.ConnectionState.Connecting
end

function Client:shutdown()
  if self:is_alive() then
    self.socket:shutdown(function()
      self.state = Client.ConnectionState.Disconnected
      if self.opts.on_disconnect ~= nil then
        vim.schedule(self.opts.on_disconnect)
      end
    end)
  end
end

--- Encodes and sends a message to the server.
--- @param type integer Message type
--- @param command string Command name
--- @param params? any Optional command parameters
function Client:send_message(type, command, params)
  if self.state ~= Client.ConnectionState.Connected then
    return
  end
  local seq = self.seq
  self.seq = seq + 1
  if params == nil then
    params = {}
  end
  local message = {
    seq = seq,
    type = type,
    command = command,
    params = params,
  }
  local content = vim.json.encode(message):gsub('"params":%[%]', '"params":{}')
  local payload = "Content-Length: " .. #content .. "\r\n\r\n" .. content
  local _, err, _ = self.socket:try_write(payload)
  if err ~= nil then
    vim.schedule(function()
      vim.notify("Failed to send data to Verse Workflow Server: " .. err,
        vim.log.levels.WARN, { title = "verse.nvim" })
    end)
  end
end

return Client
