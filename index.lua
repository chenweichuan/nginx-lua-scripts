-- CMS 推荐接口
-- @author chenweichuan@baofeng.net
--

-- 调试工具
local dump = require "dump"
dump.html = true

--[[ 函数缩写 ]]
local null = ngx.null
local print = ngx.print
local time = ngx.time
local exit = ngx.exit
local error = ngx.error
local log = ngx.log
local capture = ngx.location.capture
local getn = table.getn
local concat = table.concat
local insert = table.insert
local remove = table.remove
local sub = string.sub
local find = string.find
local len = string.len
local ceil = math.ceil
local pairs = pairs
local tonumber = tonumber
local unpack = unpack

-- 文本类型和字符集
ngx.header['Content-Type'] = "text/html;charset=utf-8"

-- 配置
local CFG = {
	memcached = {
		cache = {
			host = "127.0.0.1",
			port = 11211,
			timeout = 2000,
			pool_size = 100,
			keepalive_timeout = 120
		}
	},

	redis = {
		cache = {
			host = "127.0.0.1",
			port = 6379,
			timeout = 2000,
			pool_size = 100,
			keepalive_timeout = 120
		}
	}
}

--[[ Import lib ]]
local memcached = require "resty.memcached"
local redis = require "resty.redis"

-- [[ 自定义函数 ]]
-- 初始化memcached
local function connect_memcache( name )
	-- key 不做特殊处理
	local _memcached = memcached:new( {
		key_transform = {
			function( key )
				return key
			end,
			function( key )
				return key
			end
		}
	} )
	local cfg = CFG.memcached[name]

	_memcached:set_timeout( cfg.timeout )

	local ok, err = _memcached:connect( cfg.host, cfg.port )
	if not ok then
	    error( "memcached " .. name )
	end

	-- 附加名称
	_memcached._name = name

	return _memcached
end
-- 关闭memcached
local function close_memcache( _memcached )
	local cfg = CFG.memcached[_memcached._name]
	local ok, err = _memcached:set_keepalive( cfg.keepalive_timeout, cfg.pool_size )
end
-- 初始化redis
local function connect_redis( name )
	local _redis = redis:new()
	local cfg = CFG.redis[name]
	_redis:set_timeout(cfg.timeout)
	local ok, err = _redis:connect(cfg.host, cfg.port)
	if not ok then
	    error("redis " .. name)
	end

	if cfg.password then
		_redis:auth(cfg.password)
	end

	if cfg.dbname then
		_redis:select(cfg.dbname)
	end

	-- 附加名称
	_redis._name = name

	return _redis
end
-- 关闭redis
local function close_redis( _redis )
	local cfg = CFG.redis[_redis._name]
	local ok, err = _redis:set_keepalive( cfg.keepalive_timeout, cfg.pool_size )
end

-- 参数
local DOCUMENT_ROOT = ngx.var.document_root
local URI = ngx.var.uri
local QUERY_STRING = ngx.var.query_string or ""
local _GET = ngx.req.get_uri_args()
local PARAMS = {}

PARAMS.type = sub( URI, 2, ( find( URI, "/", 2 ) or 0 ) - 1 )
-- 若请求同时带有多个callback 参数，默认会转换为table，可通过callback[1] 判断
PARAMS.callback = _GET.callback and "" ~= ( _GET.callback[1] or _GET.callback ) and ( _GET.callback[1] or _GET.callback )

-- 读取memcache 缓存
local function get_cache_from_memcache()
	local cache_memcache = connect_memcache( "cache" )
	local res, flags, err = cache_memcache:get( URI )
	close_memcache( cache_memcache )
	return res
end
-- 读取文件缓存
local function read_cache_from_file()
	local file = io.open( DOCUMENT_ROOT .. URI, "r" )
	local contents = nil
	if file then
		contents = file:read( "*a" )
		file:close()
	end
	return contents
end
-- 读取各种推荐的缓存的方法
local switch = {}
switch["api1"] = read_cache_from_file
switch["api2"] = get_cache_from_memcache
switch["api3"] = function ()
	local cmsgpack = require "cmsgpack"

	-- do anything...

	res = {}

	return res
end

-- 验证推荐类型，并从缓存中读取结果
local result = not switch[PARAMS.type] and '["十万个冷笑话"]' or switch[PARAMS.type]()

-- 请求PHP
if not result then
	local request = capture( "/index.php?router=" .. URI .. "&" .. QUERY_STRING )

	-- 合并由php 返回的header
	for i, v in pairs( request.header ) do
		ngx.header[i] = v
	end

	result = request.body
end

-- 处理callback
if PARAMS.callback then
	result = PARAMS.callback .. "(" .. result .. ");"
end

-- 内容长度
ngx.header["Content-Length"] = len( result or "" )

-- 输出结果
print( result )
exit( 200 )
