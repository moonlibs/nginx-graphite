local socket = require 'nginx.socket'
local ngx    = require 'ngx'

local M = {}

function M:transmit(metric_msg, response_time)
	local msg  = metric_msg.." "..tostring(response_time).." "..tostring(ngx.time()).."\n"
	self.sock:send(msg)
end

local ok, metric = pcall(require, 'metric')

function M:new(params)
	assert(params and type(params) == 'table', "require params and params must be table")
	assert(params.host, "require host")
	assert(params.port and tonumber(params.port), "require port and port must be number")
	
	self.use_default_qualifier = params.use_default_qualifier
	if not ok or not metric or not metric.qualifier then
		if params.use_default_qualifier then
			metric = {}
			metric.qualifier = function()
				return {
					operation = ngx.var.request_uri:gsub('^/', ''):gsub('/', '-');
					first_prefix  = M.prefix.first;
					second_prefix = M.prefix.second;
					tx = tonumber(ngx.var.body_bytes_sent) or 0;
					rx = tonumber(ngx.var.content_length)  or 0;
				}
			end
		else
			error("Not defining qualifier method in metric module: "..tostring(metric))
		end
	end
	
	local success, r = pcall(function()
		self.prefix = {
			first  = params.prefix and params.prefix.first or '';
			second = params.prefix and params.prefix.second or '';
		}
		
		local sock = socket:new{
			host = params.host;
			port = tonumber(params.port);
		};
		sock:open()
		return sock;
	end, params)
	
	local graph = {}
	
	if not success then
		error(r)
	else
		graph.sock = r
	end
	
	setmetatable(graph , self)
	self.__index = self
	
	ngx.log(ngx.WARN, "Graphite created")
	return graph
end

function M:send()
	local response_time = ngx.now() - ngx.req.start_time()
	local success, metrics = pcall(metric.qualifier)
	if not success then return ngx.log(ngx.ERR, metrics) end
	local metric_msg = string.format('%s.hits.%s.%s.%s',
		metrics.first_prefix, metrics.second_prefix, metrics.operation, ngx.status
	)
	
	self:transmit(metric_msg, response_time)
	if metrics.rx ~= 0 then
		local rx_msg = string.format('%s.traffic.%s.%s.rx',
			metrics.first_prefix, metrics.second_prefix, metrics.operation
		)
		self:transmit(rx_msg, metrics.rx)
	end
	if metrics.tx ~= 0 then
		local tx_msg = string.format('%s.traffic.%s.%s.tx',
			metrics.first_prefix, metrics.second_prefix, metrics.operation
		)
		self:transmit(tx_msg, metrics.tx)
	end
end

return M
