local proto = require("verse.workflow_server.protocol")

local verse = require("verse")
local debug_enabled = verse.debug_enabled
local notify = verse.create_notifier("Verse Workflow")
local log_level = vim.log.levels

---@class verse.workflow_server.Client
---@field state verse.workflow_server.Client.ConnectionState
---@field socket uv.uv_tcp_t
---@field seq integer
---@field pending_reqs table<integer, fun(err:any, result:any)>
---@field opts verse.workflow_server.ClientOpts
local Client = {}
Client.__index = Client

--- @enum verse.workflow_server.Client.ConnectionState
Client.ConnectionState = {
  Connecting = 0,
  Connected = 1,
  Disconnected = 2,
  Failed = 3,
}

--- @class verse.workflow_server.ClientOpts
--- @field on_connect? fun() Post connect callback
--- @field on_disconnect? fun(err?:string) Post disconnect callback
--- @field on_notification? fun(command:string, params:any) Server Notification listener

--- @param address string
--- @param port integer
--- @param opts? verse.workflow_server.ClientOpts
function Client.connect_new(address, port, opts)
  --- @type verse.workflow_server.Client
  local self = setmetatable({}, Client)
  self.seq = 1
  self.pending_reqs = {}
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

      socket:read_start(function(...)
        self:_recv(...)
      end)

      if self.opts.on_connect ~= nil then
        vim.schedule(self.opts.on_connect)
      end
    else
      self.state = Client.ConnectionState.Failed

      vim.schedule(function()
        notify("Connection to Verse Workflow Server at " .. address .. ":" .. port .. " failed: " .. err, log_level.WARN)
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
    self.socket:read_stop()
    self.socket:shutdown(function()
      self.state = Client.ConnectionState.Disconnected
      if self.opts.on_disconnect ~= nil then
        vim.schedule(self.opts.on_disconnect)
      end
    end)
  end
end

--- @class verse.workflow_server.Message
--- @field seq integer
--- @field type verse.workflow_server.protocol.MessageType Message type
--- @field command string Command name
--- @field params? any Optional command parameters
--- @field error? any Response message error
--- @field result? any Response message result

--- Encodes and sends a message to the server.
--- @param type verse.workflow_server.protocol.MessageType Message type
--- @param command string Command name
--- @param params? any Optional command parameters
--- @param callback? fun(err:any, result:any) Response callback when type = Request
--- @return verse.workflow_server.Message|nil # Sent message
function Client:send_message(type, command, params, callback)
  if self.state ~= Client.ConnectionState.Connected then
    return nil
  end

  local seq = self.seq
  self.seq = seq + 1
  if params == nil then
    params = {}
  end

  if callback ~= nil and type == proto.MessageType.Request then
    self.pending_reqs[seq] = callback
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
    self.pending_reqs[seq] = nil
    vim.schedule(function()
      notify("Failed to send data to Verse Workflow Server: " .. err, log_level.WARN)
    end)
    return nil
  end

  return message
end

--- @param content any
--- @return verse.workflow_server.Message|nil
local function validate_message_payload(content)
  if type(content) ~= "string" then
    return nil
  end
  local ok, json = pcall(vim.json.decode, content, {
    luanil = {
      object = true,
      array = true,
    }
  })
  if not ok or json == nil then
    if debug_enabled() then
      notify("Failed to decode payload from Verse Workflow Server: " .. content, log_level.DEBUG)
    end
    return nil
  end

  if type(json["seq"]) == "number"
    and type(json["type"]) == "number"
    and type(json["command"]) == "string"
  then
    return json
  else
    if debug_enabled() then
      notify("Received unexpected JSON from Verse Workflow Server: " .. content, log_level.DEBUG)
    end
    return nil
  end
end

--- @param err uv.callback.err
--- @param data string?
function Client:_recv(err, data)
  if err ~= nil then
    if debug_enabled() then
      vim.schedule(function()
        notify("Error receiving data from Verse Workflow Server: " .. err, log_level.DEBUG)
      end)
    end
    return
  elseif data == nil then
    vim.schedule(function()
      notify("Connection to Verse Workflow Server terminated")
    end)
    self:shutdown()
    return
  end

  local payloads = {}
  local find_start = 1
  while true do
    local _, j, content_len = data:find("Content%-Length: (%d+)\r\n\r\n", find_start)
    if j ~= nil then
      find_start = j + content_len + 1
      local content = data:sub(j + 1, j + content_len)
      table.insert(payloads, content)
    else
      break
    end
  end
  if #payloads == 0 then
    return
  end

  vim.schedule(function()
    for _, payload in ipairs(payloads) do
      local message = validate_message_payload(payload)
      if message ~= nil then
        self:_handle_message(message)
      end
    end
  end)
end

--- @param message verse.workflow_server.Message
function Client:_handle_message(message)
  if message.type == proto.MessageType.Notification then
    if self.opts.on_notification ~= nil then
      self.opts.on_notification(message.command, message.params)
    end
  elseif message.type == proto.MessageType.Response and type(message.seq) == "number" then
    local callback = self.pending_reqs[message.seq]
    if callback ~= nil then
      callback(message.error, message.result)
    end
  elseif debug_enabled() then
    notify("Unhandled Verse Workflow Server message: " .. vim.inspect(message), log_level.DEBUG)
  end
end

return Client
