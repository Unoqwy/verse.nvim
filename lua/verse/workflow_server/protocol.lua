local M = {}

M.MessageType = {
  Notification = 0,
  Request = 1,
  Response = 2,
}

M.BuildState = {
  Success = 0,
  Warning = 1,
  Errors = 2,
  Building = 3,
  NoBuild = 4,
}

return M
