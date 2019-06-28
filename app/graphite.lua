local socket = require 'nginx.socket'
local ngx    = require 'ngx'
local ffi    = require 'ffi'

local M = {}

ffi.cdef[[
	int snprintf(char *str, size_t, const char *format, ...);
]]

local C = ffi.C
-- max uri length is 16 Kbyte on nginx
local buff_size = 16 * 1024
local message = ffi.new("char[?]", buff_size)

function M:transmit(prefix, t, operation, field, value)
	local n = C.snprintf(message, buff_size, "%s.%s.%s.%s %.0f %.0f\n",
		prefix, t, operation, tostring(field), value, ngx.time()
	)
	self.sock:send(message, n)
end

function M:qualifier()
	return {ngx.req.get_method(), {"hits", "traffic_tx", "traffic_rx"}}
end

function M:hits(prefix, operation)
	self:transmit(prefix, 'hits', operation, ngx.status, ngx.now() - ngx.req.start_time())
end

function M:traffic_tx(prefix, operation)
	local tx = tonumber(ngx.var.body_bytes_sent) or 0
	if tx ~= 0 then
		self:transmit(prefix, 'traffic', operation, 'tx', tx)
	end
end

function M:traffic_rx(prefix, operation)
	local rx = tonumber(ngx.var.content_length) or 0
	if rx ~= 0 then
		self:transmit(prefix, 'traffic', operation, 'rx', rx)
	end
end

function M:new(params)
	assert(params and type(params) == 'table', "require params and params must be table")
	assert(params.host, "require host")
	assert(params.port and tonumber(params.port), "require port and port must be number")
	assert(params.prefix and type(params.prefix) == 'string', "require prefix and prefix must be string")
	
	local graph  = {
		prefix = params.prefix;
	}
	
	local success, result = pcall(function(params)
		local sock = socket:new{
			host = params.host;
			port = tonumber(params.port);
		}
		sock:open()
		return sock
	end, params)
	if not success or not result then
		error(result)
	end
	
	graph.sock = result
	setmetatable(graph, self)
	self.__index = self
	
	return graph
end

function M:send(...)
	-- operation[1] - metric name
	-- operation[2] - list of metric's types
	-- operation[3] - reserved for internal usage
	-- operation[4] - reserved for internal usage
	local success, operation = pcall(self.qualifier, self, ...)
	if not success then return ngx.log(ngx.ERR, tostring(operation)) end
	if not operation then return end
	if not operation[2] then
		error("Operation list required for "..tostring(operation[1]), 2)
	end
	local host = string.gsub(ngx.var.host, "%.", "-")
	local op = string.format("%s.%s", host, operation[1])
	local prefix = self.prefix
	for i = 1, #operation[2] do
		M[operation[2][i]](self, prefix, op)
	end
end

return M
