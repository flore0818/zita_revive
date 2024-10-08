Time=love.timer.getTime
love._openConsole()
--------------------------------------------------------------
require'Zenitha'
ZENITHA.setMaxFPS(30)
ZENITHA.setDrawFreq(10)
ZENITHA.setUpdateFreq(100)
ZENITHA.setVersionText('')
function SimpStr(s) return s:gsub('%s',''):lower() end
local esc={{'&amp;','&'},{'&#91;','['},{'&#93;',']'},{'&#44;',','}}
function RawStr(s) for _,v in next,esc do s=s:gsub(v[1],v[2]) end return s end
--------------------------------------------------------------
local ws=WS.new{
    host='localhost',
    port='3001',
    connTimeout=2.6,
    sleepInterval=0.1,
}
Config={
    adminName="管理员",
    receiveDelay=0.26,
    maxCharge=620,
    debugLog_send=false,
    debugLog_receive=false,
    debugLog_response=false,
    safeMode=false,
    superAdminID={},
    groupManaging={},
    safeSessionID={},
}
xpcall(function()
    local data=FILE.load('conf.luaon','-luaon')
    Config.adminName=data.adminName
    Config.superAdminID=TABLE.getValueSet(data.superAdminID)
    Config.groupManaging=TABLE.getValueSet(data.groupManaging)
    Config.safeSessionID=TABLE.getValueSet(data.safeSessionID)
    Config.extraData=data.extraData
    print("conf.luaon successfully loaded")
end,function(mes)
    print("Error in loading conf.luaon: "..mes)
    print("Some settings may not be loaded correctly")
end)
print("--------------------------")
print("Admin name: "..Config.adminName)
print("# Super admin ID:")
for id in next,Config.superAdminID do print(id) end
print("# Group managing:")
for id in next,Config.groupManaging do print(id) end
print("# Safe session ID:")
for id in next,Config.safeSessionID do print(id) end
--------------------------------------------------------------
Bot={
    taskPriv={
        {'log',-100},
        {'admin_control',-99},
        {'help_public',1},
        {'zictionary',2},
        {'phtool',3},
    },
    taskGroup={
        {'log',-100},
        {'admin_control',-99},
        {'help_public',1},
        {'zictionary',2},
        {'repeater',100},
    },
    stat={
        connectAttempts=0,
        launchTime=Time(),
        totalMessageSent=0,

        connectLogDelay=0,
        connectLogDelaySum=0,

        connectTime=Time(),
        messageSent=0,
    },
}

---@class Task_raw
---@field func fun(S:Session, M: LLOneBot.Event.Message, D:Session.data):boolean
---@field init fun(S:Session, D:Session.data)?

---@class Task : Task_raw
---@field id string
---@field prio number

function Bot.isAdmin(id)
    return Config.superAdminID[id]
end

---@param data LLOneBot.SimpMes
function Bot.send(data)
    local mes={
        action='send_msg',
        params={
            user_id=data.user,
            group_id=data.group,
            message=data.message,
        }
    }
    if Config.safeMode and not Config.safeSessionID['p'..data.user or 'g'..data.group] then
        if TASK.lock('safeModeBlock',10) then
            print("Message blocked in safe mode")
        end
        return
    end
    local suc,res=pcall(JSON.encode,mes)
    if suc then
        if Config.debugLog_send then
            print(TABLE.dump(mes))
        end
        ws:send(res)
        Bot.stat.messageSent=Bot.stat.messageSent+1
        Bot.stat.totalMessageSent=Bot.stat.totalMessageSent+1
    else
        print("Error encoding json:\n"..debug.traceback(res))
    end
end
function Bot.adminNotice(text)
    for id in next,Config.superAdminID do
        Bot.send{user=id,message=text}
    end
end
function Bot.restart()
    for id in next,SessionMap do
        SessionMap[id]=nil
    end
end
function Bot.stop(time)
    TASK.forceLock('bot_lock',time or 600)
    ws:close()
end

function Bot.help()
    local cmds=TABLE.getKeys(Bot)
    table.sort(cmds)
end

---@return true? #if any message processed
function Bot._update()
    local pack,op=ws:receive()
    if not pack then return end
    if op=='text' then
        local suc,res=pcall(JSON.decode,pack)
        ---@cast res LLOneBot.Event.Base
        if not suc then
            print("Error decoding json: "..res)
            print(pack)
            return true
        end
        if res.post_type=='meta_event' then
            ---@cast res LLOneBot.Event.Meta
            if res.meta_event_type=='lifecycle' then
                print("Lifecycle event: "..res.sub_type)
            end
        elseif res.retcode then
            ---@cast res LLOneBot.Event.Response
            if Config.debugLog_response then
                print(TABLE.dump(res))
            end
        elseif res.post_type=='message' then
            ---@cast res LLOneBot.Event.Message
            local priv=res.message_type=='private'
            local id=priv and res.user_id or res.group_id
            local S=SessionMap[(priv and 'p' or 'g')..id]
            if not S then
                S=Session.new(id,priv)
                SessionMap[S.uid]=S
            end
            S:receive(res)
        elseif res.post_type=='notice' then
            -- TODO
        elseif res.post_type=='request' then
            -- TODO
        end
    elseif op~='pong' then
        print("[inside: "..op.."]")
        if type(pack)=='string' and #pack>0 then print(pack) end
    end
    return true
end
--------------------------------------------------------------
---@alias Session.data table
---@class Session
---@field id number
---@field uid string just 'p' or 'g' + id, for being used as unique key in SessionMap
---@field priv boolean
---@field group boolean #not priv
---@field taskList Task[]
---@field locks Map<number>
---@field checkpoints Map<number>
---@field data Map<Session.data>
---
---@field createTime number
---@field charge number
---@field maxCharge number
---@field lastUpdateTime number
Session={}

local lockMapMeta={
    __index=function(self,k) rawset(self,k,-1e99) return -1e99 end,
    __newindex=function(self,k) rawset(self,k,-1e99) end,
}
---@return Session
function Session.new(id,priv)
    ---@type Session
    local s={
        id=id,
        uid=(priv and 'p' or 'g')..id,
        priv=priv,
        group=not priv,
        admin=not priv and Config.groupManaging[id],
        taskList={},
        locks=setmetatable({},lockMapMeta),
        checkpoints={},
        data={},

        createTime=Time(),
        charge=Config.maxCharge,
        maxCharge=Config.maxCharge,
        lastUpdateTime=Time(),
    }
    setmetatable(s,{__index=Session})

    local template=priv and Bot.taskPriv or Bot.taskGroup
    for _,task in next,template do
        s:newTask(task[1],task[2])
    end
    return s
end

---@param id string Task name
---@param prio number Task priority
function Session:newTask(id,prio)
    ---@type Task_raw
    local task=require('task.'..id)
    local insPos
    for i=1,#self.taskList do
        local t=self.taskList[i]
        if id==t.id then
            print("Task created failed: Task '"..task.."' already exists")
            return
        elseif prio==t.prio then
            print("Task created failed: Prio '"..prio.."' already used by task '"..t.id.."'")
            return
        elseif not insPos and prio<t.prio then
            insPos=i
        end
    end
    if not insPos then insPos=#self.taskList+1 end
    table.insert(self.taskList,insPos,{
        prio=prio,
        id=id,
        func=task.func,
    })
    self.data[id]={}
    if task.init then task.init(self,self.data[id]) end
end
---@param id string
function Session:removeTask_id(id)
    for i=1,#self.taskList do
        if self.taskList[i].id==id then
            print("Task removed: "..id)
            table.remove(self.taskList,i)
            return
        end
    end
end
function Session:removeAllTask()
    for id,task in next,self.taskList do
        if task.prio>0 then
            self.taskList[id]=nil
        end
    end
    print("All user tasks cleared")
end

---@param name any
---@param time? number
---@return boolean
function Session:lock(name,time)
    if Time()>=self.locks[name] then
        self.locks[name]=Time()+(time or 1e99)
        return true
    else
        return false
    end
end
---@param name any
---@param time? number
---@return boolean
function Session:forceLock(name,time)
    local res=Time()>=self.locks[name]
    self.locks[name]=Time()+(time or 1e99)
    return res
end
---@param name any
function Session:unlock(name)
    self.locks[name]=-1e99
end
---@param name any
---@return number|false
function Session:getLock(name)
    local v=self.locks[name]-Time()
    return v>0 and v
end
function Session:freshLock()
    for k,v in next,self.locks do
        if Time()>v then self.locks[k]=nil end
    end
end
function Session:clearLock()
    for k in next,self.locks do
        self.locks[k]=nil
    end
end

function Session:setTimeCheckpoint(name)
    self.checkpoints[name]=Time()
end
function Session:getTimeCheckpoint(name)
    return Time()-(self.checkpoints[name] or self.createTime)
end

function Session:update()
    self.charge=math.min(self.charge+(Time()-self.lastUpdateTime),self.maxCharge)
    self.lastUpdateTime=Time()
end
function Session:costCharge(charge)
    self:update()
    if self.charge>=charge then
        self.charge=self.charge-charge
        return true
    else
        return false
    end
end
function Session:useCharge(charge)
    self:update()
    self.charge=math.max(self.charge-charge,0)
end

function Session:receive(M)
    for _,task in next,self.taskList do
        local suc2,res2=pcall(task.func,self,M,self.data[task.id])
        if suc2 then
            if res2==true then break end
        else
            print(STRING.repD("Session-$1 Task-$2 Error:\n$3",self.id,task.id,res2))
            break
        end
    end
end
function Session:send(text)
    if self.priv then
        Bot.send{user=self.id,message=text}
    else
        Bot.send{group=self.id,message=text}
    end
end

---@type table<string, Session>
SessionMap={}
--------------------------------------------------------------
ZENITHA.globalEvent.drawCursor=NULL
ZENITHA.globalEvent.clickFX=NULL
local scene={}

function scene.load() end
function scene.update()
    if ws.state=='dead' then
        if TASK.getLock('bot_lock') then return end
        TASK.unlock('bot_running')
        Bot.stat.connectAttempts=Bot.stat.connectAttempts+1
        Bot.stat.connectLogDelay=10
        Bot.stat.connectLogDelaySum=0
        TASK.forceLock('connect_message',Bot.stat.connectLogDelay)
        ws:connect()
        print("--------------------------")
        print("Connecting to LLOneBot...")
    elseif ws.state=='connecting' then
        ws:update()
        if TASK.lock('connect_message',Bot.stat.connectLogDelay) then
            Bot.stat.connectLogDelaySum=Bot.stat.connectLogDelaySum+Bot.stat.connectLogDelay
            print(STRING.repD("Connecting... ($1s taken)",Bot.stat.connectLogDelaySum))
            Bot.stat.connectLogDelay=math.min(Bot.stat.connectLogDelay*2,3600)
        end
    elseif ws.state=='running' then
        if not TASK.getLock('bot_running') then
            TASK.lock('bot_running')
            print("CONNECTED")
            if TABLE.find(arg,"startWithNotice") then
                Bot.adminNotice(Bot.stat.connectAttempts==1 and "小z启动了喵！" or STRING.repD("小z回来了喵…（第$1次）",Bot.stat.connectAttempts))
            end
        end
        repeat until not Bot._update()
    end
end
function scene.keyDown(k)
    if k=='s' then
        print("--------------------------")
        print("Statistics:")
        print("Alive time: "..STRING.time(Time()-Bot.stat.connectTime))
        print("Messages sent: "..Bot.stat.messageSent)
    end
end
function scene.draw() end
function scene.unload() end

SCN.add('main', scene)
ZENITHA.setFirstScene('main')

TASK.new(function()
    while true do
        TASK.yieldT(10*60)
        if TASK.getLock('bot_running') then
            TASK.freshLock()
            for _,S in next,SessionMap do
                S:freshLock()
            end
        end
    end
end)

print("--------------------------")
for i=1,#Bot.taskPriv do require('task.'..Bot.taskPriv[i][1]) end
for i=1,#Bot.taskGroup do require('task.'..Bot.taskGroup[i][1]) end
