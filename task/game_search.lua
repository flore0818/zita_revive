local tags="电脑 手机 主机 网页 键盘 触屏 鼠标 单人 多人 快速 慢速 题库 新人"
local tagRedirect={
    ["电脑版"]="电脑",["手机版"]="手机",
    ["浏览器"]="网页",["网页版"]="网页",
    ["单机"]="单人",["对战"]="多人",
    ["无延迟"]="快速",["延迟块"]="慢速",
}
local gameData={
    -- 多人（热）
    {name="tech",        tags="电脑 手机 键盘 触屏 单人 多人 快速 慢速 新人"},
    {name="io",          tags="电脑 网页 单人 多人 键盘 快速 新人"},
    {name="js",          tags="电脑 手机 网页 单人 多人 键盘 触屏 快速 新人"},
    {name="tec",         tags="电脑 主机 单人 多人 键盘 鼠标 慢速 新人"},

    -- 单机（热）
    {name="tetrjs",      tags="电脑 手机 网页 单人 键盘 触屏 快速 慢速 新人"},
    {name="tgm",         tags="电脑 单人 键盘 快速"},
    {name="tl",          tags="电脑 网页 单人 键盘 快速 慢速"},
    {name="asc",         tags="电脑 网页 单人 键盘 快速 慢速"},
    {name="np",          tags="电脑 单人 键盘 快速 慢速"},
    {name="misa",        tags="电脑 单人 键盘 慢速"},
    {name="touhoumino",  tags="电脑 单人 键盘 快速"},
    {name="royale",      tags="手机 单人 触屏 快速 慢速"},

    -- 单机（冷）
    {name="mind bender", tags="电脑 手机 网页 单人 键盘 触屏 鼠标 快速 慢速"},
    {name="gems",        tags="电脑 手机 网页 单人 键盘 触屏 鼠标 快速 慢速"},
    {name="tetris.com",  tags="电脑 手机 网页 单人 键盘 触屏 鼠标 快速 慢速"},
    {name="dtet",        tags="电脑 单人 键盘 快速"},
    {name="cambridge",   tags="电脑 单人 键盘 快速 慢速"},
    {name="hebo",        tags="电脑 单人 键盘 快速"},
    {name="texmaster",   tags="电脑 单人 键盘 快速"},
    {name="tetris beat", tags="手机 单人 触屏 快速 慢速"},

    -- 多人（冷）
    {name="kos",         tags="电脑 手机 网页 单人 多人 键盘 触屏 鼠标 慢速"},
    {name="to",          tags="电脑 单人 多人 键盘 快速"},
    {name="c2",          tags="电脑 单人 多人 键盘 快速"},
    {name="nuke",        tags="电脑 网页 单人 多人 键盘 慢速"},
    {name="wwc",         tags="电脑 网页 单人 多人 键盘 快速 慢速"},
    {name="tf",          tags="电脑 网页 单人 多人 键盘 快速 慢速"},
    {name="jj",          tags="手机 单人 多人 触屏 快速"},
    -- {name="fl",          tags="电脑 手机 网页 键盘 触屏 单人 多人 经典 现代 快速 慢速"},-- 目前好像上不去

    -- 主机 & 题库
    {name="ppt",         tags="电脑 主机 单人 多人 键盘 慢速"},
    {name="t99",         tags="主机 单人 多人 键盘 慢速"},
    {name="ttt",         tags="电脑 网页 单人 键盘 题库"},
    {name="ttpc",        tags="电脑 网页 单人 键盘 题库"},
    {name="tpo",         tags="电脑 网页 单人 键盘 题库"},
    {name="nazo",        tags="电脑 网页 单人 键盘 题库"},
}

---@type Task_raw
return {
    func=function(S,M)
        local words=STRING.split(STRING.trim(RawStr(M.raw_message)),'%s+',true)
        for i=1,#words do
            MSG.new('info',words[i])
        end
        if not (words[1]=="#游戏" or words[1]=="#game") then return false end
        table.remove(words,1)
        if #words==0 then
            if S:lock('game_search_help',26) then
                S:send("发送“#游戏 标签1 标签2…”来筛选你能接受的方块游戏，可用的tag："..tags)
            end
        else
            if not S:lock('game_search',6.26) then return true end
            if not S:costCharge(126) then
                if S:forceLock('searchCharge',26) then S:send("词典能量耗尽！请稍后再试喵") end
                return true
            end

            -- Remove too long words
            for i=#words,1,-1 do
                if #words[i]>=10 then
                    table.remove(words,i)
                end
            end

            -- Remove too many words
            while #words>10 do
                table.remove(words)
            end

            -- Remove invalid tags
            local filtered=false
            for i=#words,1,-1 do
                if not tags:find(words[i]) then
                    table.remove(words,i)
                    filtered=true
                end
            end

            local results={}
            for _,game in next,gameData do
                local available=true
                for _,word in next,words do
                    if tagRedirect[word] then
                        word=tagRedirect[word]
                    end
                    if not game.tags:find(word) then
                        available=false
                        break
                    end
                end
                if available then
                    table.insert(results,game.name)
                end
            end

            if #results==0 then
                S:send("没有符合条件的游戏喵…")
            else
                local count=#results
                if count>10 then
                    results=TABLE.sub(results,1,10)
                end
                local resultStr=STRING.repD("找到了$1个游戏，使用#xxx查看详细信息：\n$2",count,table.concat(results,", "))
                if count>10 then resultStr="(只显示前十个)"..resultStr end
                if filtered then resultStr="(忽略无效标签)"..resultStr end
                S:send(resultStr)
            end
        end
        return true
    end,
}
