module RedisExtensions
  def increment_if_exists(key)
    lua_script = <<~LUA
      local key = KEYS[1]
      
      if redis.call('EXISTS', key) == 1 then
        return redis.call('INCR', key)
      else
        return nil
      end
    LUA
    
    result = eval(lua_script, keys: [key])
    result
  end

  def increment_with_default_value(key, default_value)
    lua_script = <<~LUA
      local key = KEYS[1]
      local default_value = tonumber(ARGV[1])
      
      local was_set = redis.call('SETNX', key, default_value)
      return redis.call('INCR', key)
    LUA
    
    result = eval(lua_script, keys: [key], argv: [default_value])
    result
  end
end

Redis.include RedisExtensions
