local enumerable = {}

local eval_cache = {}

enumerable.enumerate = function(t)
    local iterator, table, key = pairs(t)
    return function(t, k)
        local key, value = iterator(t, k)
        return value, key
    end, table, key
end

enumerable.count = function(t, ...)
    local count = 0

    if select('#', ...) == 0 or type(...) == 'table' then
        for _ in pairs(t) do
            count = count + 1
        end
    else
        for _, el in pairs(t) do
            if (...)(el) == true then
                count = count + 1
            end
        end
    end

    return count
end

enumerable.any = function(t, ...)
    if select('#', ...) == 0 then
        for _ in pairs(t) do
            return true
        end

        return false
    end

    for _, v in pairs(t) do
        if (...)(v) == true then
            return true
        end
    end

    return false
end

enumerable.all = function(t, fn)
    for _, v in pairs(t) do
        if fn(v) == false then
            return false
        end
    end

    return true
end

enumerable.contains = function(t, search)
    for _, el in pairs(t) do
        if el == search then
            return true
        end
    end

    return false
end

enumerable.totable = function(t)
    local arr = {}
    local key = 0
    for _, el in pairs(t) do
        key = key + 1
        arr[key] = el
    end

    return arr
end

enumerable.aggregate = function(t, fn, ...)
    local initialized = select('#', ...) > 0
    local res = ...

    for key, el in pairs(t) do
        if not initialized then
            res = el
            initialized = true
        else
            res = fn(res, el, key, t)
        end
    end

    return res
end

local redirect = {
    add = {
        copy = function(constructor, add, t)
            local res = constructor()
            for _, el in pairs(t) do
                add(res, el)
            end

            return res
        end,
        select = function(constructor, add, t, fn)
            local res = constructor()

            for key, el in pairs(t) do
                add(res, fn(el, key, t))
            end

            return res
        end,
        where = function(constructor, add, t, fn)
            local res = constructor()

            for key, el in pairs(t) do
                if fn(el, key, t) then
                    add(res, el)
                end
            end

            return res
        end,
    },
    remove = {
        clear = function(constructor, remove, t)
            for key in pairs(t) do
                remove(t, key)
            end

            return t
        end,
    },
}

local build_index = function(constructor, proxies)
    local index = {}

    for name, fn in pairs(proxies) do
        index[name] = fn
    end

    for name, fn in pairs(enumerable) do
        index[name] = fn
    end

    if constructor ~= nil then
        for proxy_name, proxy in pairs(proxies) do
            for name, fn in pairs(redirect[proxy_name]) do
                index[name] = function(...)
                    return fn(constructor, proxy, ...)
                end
            end
        end
    end

    return index
end

local evaluate = function(t, index)
    if index == nil or eval_cache[t] == nil then
        return index
    end

    for _ in pairs(t) do
    end
end

local index_cache = {}
return function(meta, name)
    local constructor = meta.__create
    local add = meta.__add_element
    local remove = meta.__remove_key

    local index = build_index(meta.__create, {
        add = add,
        remove = remove,
    })
    index_cache[#index_cache + 1] = index

    -- __index
    local original = meta.__index
    local index_type = type(original)
    if index_type == 'nil' then
        meta.__index = index
    elseif index_type == 'table' then
        meta.__index = function(t, k)
            return evaluate(t, original[k]) or index[k]
        end
    elseif index_type == 'function' then
        meta.__index = function(t, k)
            return evaluate(t, original(t, k)) or index[k]
        end
    else
        error(('Unknown indexing index_type: %s'):format(type))
    end

    local get_index = function(key)
        return type(meta.__index) == 'table' and meta.__index[key] or meta.__index(nil, key)
    end

    -- __len
    if meta.__len == nil then
        meta.__len = get_index('count')
    end

    -- Lazy evaluation
    -- If __pairs is not provided, it should default to pairs, but we can't use pairs itself
    -- or it will go to the __pairs metamethod again and infinitely recurse, so we provide a
    -- custom pairs implementation
    local enumerator = meta.__pairs or function(t)
        return function(t, k)
            local key = next(t, k)
            return key, t[key]
        end, t, nil
    end
    meta.__pairs = function(original)
        local cache = eval_cache[original]
        if cache == nil then
            return enumerator(original)
        end

        local fn, args = unpack(cache)
        local iterator, table, key = pairs(args)
        return function(t, k)
            local key, value = iterator(t, k)
            if key == nil then
                return nil, nil
            end
            fn(original, value, key)
            return key, value
        end, table, key
    end

    -- Implement toX function as a constructor call
    if name ~= nil then
        local key = 'to' .. name
        enumerable[key] = constructor
        for _, index in pairs(index_cache) do
            index[key] = constructor
        end
    end

    return meta.__create
end

--[[
Copyright © 2016, Windower
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of Windower nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Windower BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

