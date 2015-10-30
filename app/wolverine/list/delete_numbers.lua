local phone_numbers = cjson.decode(ARGV[1])
local set_keys      = {}
local stat_keys     = {}
local removed_count = 0
set_keys.active     = KEYS[1]
set_keys.presented  = KEYS[2]
set_keys.completed  = KEYS[3]
set_keys.failed     = KEYS[4]
set_keys.blocked    = KEYS[5]
set_keys.bin        = KEYS[6]
stat_keys.list      = KEYS[7]
stat_keys.campaign  = KEYS[8]

for _,key in pairs(set_keys) do
  removed_count = redis.call('ZREM', key, unpack(phone_numbers))
end

if removed_count > 0 then
  local incrby = 0 - removed_count
  redis.call('HINCRBY', stat_keys.campaign, 'total_numbers', incrby)
end

redis.call('HSET', stat_keys.list, 'total_numbers', #phone_numbers)

return removed_count
