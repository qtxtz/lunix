#!/bin/sh
_=[[
	. "${0%/*}/regress.sh"
	exec runlua -r5.2 "$0" "$@"
]]

local unix = require"unix"
local regress = require"regress".export".*"

local function strname(addr)
	local ip, port = assert(unix.getnameinfo(addr, unix.NI_NUMERICHOST + unix.NI_NUMERICSERV))
	return string.format("[%s]:%d", ip, tonumber(port))
end

local function setnonblock(fd)
	local flags = assert(unix.fcntl(fd, unix.F_GETFL))
	assert(unix.fcntl(fd, unix.F_SETFL, flags + unix.O_NONBLOCK))
end

local function setrecvaddr(fd, family)
	local type, level
	if family == unix.AF_INET6 then
		level = unix.IPPROTO_IPV6
		type = unix.IPV6_RECVPKTINFO or unix.IPV6_PKTINFO
	else
		level = unix.IPPROTO_IP
		type = unix.IP_RECVDSTADDR or unix.IP_PKTINFO
	end

	assert(unix.setsockopt(fd, level, type, true))
end

local function in_addr_any(family)
	return family == unix.AF_INET6 and "::" or "0.0.0.0"
end

local function do_recvfromto(family, port)
	local sd = assert(unix.socket(family, unix.SOCK_DGRAM))
	assert(unix.bind(sd, { family = family, addr = in_addr_any(family), port = port }))
	setnonblock(sd)
	setrecvaddr(sd, family)

	local fd = assert(unix.socket(family, unix.SOCK_DGRAM))
	-- NB: FreeBSD requires binding to IN_ADDR_ANY
	assert(unix.bind(fd, { family = family, addr = in_addr_any(family), port = 0 }))
	setnonblock(fd)

	for ifa in unix.getifaddrs() do
		if ifa.family == family then
			local to = { family = family, addr = ifa.addr, port = port }
			local from = { family = family, addr = ifa.addr, port = port + 1 }
			assert(unix.sendtofrom(fd, "hello world", 0, to, from))
			info("sendtofrom (to:%s from:%s)", strname(to), strname(from))

			local msg, from, to = assert(unix.recvfromto(sd, 512, 0))
			info("recvfromto -> (msg:%s from:%s to:%s)", msg, strname(from), strname(to))
		end
	end
end

for _,family in ipairs{ unix.AF_INET, unix.AF_INET6 } do
	do_recvfromto(family, 8000)
end

say"OK"
