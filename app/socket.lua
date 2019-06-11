local ffi = require 'ffi'
local ngx = require 'ngx'
local C   = ffi.C

local M = {}

ffi.cdef[[
	static const int AF_INET    = 2;
	static const int SOCK_DGRAM = 2;
	
	typedef unsigned short int sa_family_t;
	typedef uint16_t in_port_t;
	typedef uint32_t in_addr_t;
	typedef uint32_t socklen_t;
	typedef int ssize_t;
	
	struct sockaddr {
		sa_family_t    sin_family;
		char           sa_data[14];  /* 14 bytes of protocol address */
	};
	
	struct in_addr {
		uint32_t s_addr;             /* address in network byte order */
	};
	
	struct sockaddr_in {
		sa_family_t    sin_family;
		in_port_t      sin_port;
		struct in_addr sin_addr;
		unsigned char sin_zero[sizeof(struct sockaddr)-sizeof(sa_family_t)-sizeof(in_port_t)-sizeof(struct in_addr)];
	};
	
	int inet_aton(const char *cp, struct in_addr *inp);
	
	int socket(int domain, int type, int protocol);
	int close(int fd);
	
	uint16_t htons (uint16_t hostshort);
	
	ssize_t sendto(
		int sockfd,
		const void *buf,
		size_t len,
		int flags,
		const struct sockaddr *dest_addr,
		socklen_t addrlen
	);
	
	char *strerror(int errnum);
]]

local AF_INET    = C.AF_INET
local SOCK_DGRAM = C.SOCK_DGRAM
local inet_aton  = C.inet_aton
local socket     = C.socket
local close      = C.close
local htons      = C.htons
local sendto     = C.sendto
local strerror   = C.strerror

function M:new(params)
	local sock = {
		host = params.host;
		port = params.port;
		error_cnt = 0;
	}
	setmetatable(sock, self)
	self.__index = self
	return sock
end

function M:open()
	-- attempt to open socket
	for i = 1, 3 do
		self.sockfd = socket(AF_INET, SOCK_DGRAM, 0)
		if self.sockfd ~= -1 then break end
		if i ~= 3 then
			ngx.log(ngx.ALERT, "[ALERT_NG_SOCK] Failed attempt to open socket number: "..i)
			error "Impossible to open socket"
		end
	end
	
	local addr = ffi.new("struct sockaddr_in")
	addr.sin_family = AF_INET
	addr.sin_port = htons(self.port)
	inet_aton(self.host, addr.sin_addr)
	
	self.dest_addr = ffi.cast("struct sockaddr *", addr)
	self.addr_len  = ffi.cast("socklen_t", ffi.sizeof(addr))
	self.addr = addr
	ngx.log(ngx.WARN, string.format("Socket on %s:%d opened", self.host, tonumber(self.port)))
end

function M:close()
	close(self.sockfd)
	ngx.log(ngx.WARN, string.format("Socket on %s:%d closed", self.host, tonumber(self.port)))
end

function M:send(msg)
	msg = tostring(msg)
	local r = sendto(self.sockfd, msg, #msg, 0, self.dest_addr, self.addr_len)
	if r == -1 then self:error() end
end

function M:error()
	self.error_cnt = self.error_cnt + 1
	ngx.log(ngx.ALERT, ffi.string(strerror(ffi.errno())))
	ngx.log(ngx.ALERT, "[ALERT_NG_SOCK] Error count: "..self.error_cnt)
	
	-- if socket not work correctly then reopen it
	if (self.error_cnt > 10) then
		self:close()
		self:open()
		self.error_cnt = 0
	end
end

return M
