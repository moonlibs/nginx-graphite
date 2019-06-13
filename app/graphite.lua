local socket = require 'nginx.socket'
local ngx    = require 'ngx'

local M = {}

function M:transmit(metric_msg)
	local msg  = string.format("%s %s %s\n", metric_msg, tostring(ngx.time()))
	self.sock:send(msg)
end

function M:new(params)
	assert(params and type(params) == 'table', "require params and params must be table")
	assert(params.host, "require host")
	assert(params.port and tonumber(params.port), "require port and port must be number")
	assert(params.prefix and type(params.prefix) == 'function', "require prefix and prefix must be function")

	local graph  = {
		metric = {};
		prefix = params.prefix;
	}

	if params.use_default_metrics then
		graph.metric = {
			operation_qualifier = function()
				return ngx.var.request_uri:gsub('^/', ''):gsub('/', '-');
			end;
			form = {
				hits = function(operation)
					local response_time = ngx.now() - ngx.req.start_time()
					return string.format('%s.hits.%s.%s %s', self.prefix(), operation, ngx.status, response_time)
				end;
				traffic_tx = function(operation)
					local tx = tonumber(ngx.var.body_bytes_sent) or 0;
					if tx ~= 0 then
						return string.format('%s.traffic.%s.tx %s', self.prefix(), operation, tx)
					end
					return
				end;
				traffic_rx = function(operation)
					local rx = tonumber(ngx.var.content_length) or 0;
					if rx ~= 0 then
						return string.format('%s.traffic.%s.rx %s', self.prefix(), operation, rx)
					end
					return
				end;
			};
		}
	else
		local ok, res = pcall(require, 'metric')
		if not ok or not res then
			error(string.format("Impossible to load metric module. Res=%s", tostring(res)))
		end
		if not res.operation_qualifier then
			error("No operation_qualifier function in metric module")
		end
		if not res.form then
			error("No form function in metric module")
		end
		graph.metric = res
	end

	local success, result = pcall(function(params)
		local sock = socket:new{
			host = params.host;
			port = tonumber(params.port);
		};
		sock:open()
		return sock;
	end, params)
	if not success or not result then
		error(result)
	end

	graph.sock = result
	setmetatable(graph , self)
	self.__index = self
	
	ngx.log(ngx.WARN, "Graphite created")
	return graph
end

function M:send()
	local success, operation = pcall(self.metric.operation_qualifier)
	if not success then return ngx.log(ngx.ERR, operation) end
	local host = string.gsub(ngx.var.host, "%.", "-")
	for name, form_message in pairs(self.metric.form) do
		local msg = form_message(operation, host)
		if msg then self:transmit(msg) end
	end
end

return M
