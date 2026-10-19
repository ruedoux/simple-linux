local lib = {}

function lib.rebind(keys, dispatcher, opts)
  hl.unbind(keys)
  hl.bind(keys, dispatcher, opts)
end

return lib
