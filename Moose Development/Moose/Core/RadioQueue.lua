--- **Core** - Queues Radio Transmissions.
-- 
-- ===
-- 
-- ## Features:
-- 
--   * Managed Radio Transmissions.
--
-- ===
--
-- ### Authors: funkyfranky
--
-- @module Core.RadioQueue
-- @image Core_Radio.JPG

--- Manages radio transmissions.
-- 
-- @type RADIOQUEUE
-- @field #string ClassName Name of the class "RADIOQUEUE".
-- @field #boolean Debug Debug mode. More info.
-- @field #string lid ID for dcs.log.
-- @field #number frequency The radio frequency in Hz.
-- @field #number modulation The radio modulation. Either radio.modulation.AM or radio.modulation.FM.
-- @field Core.Scheduler#SCHEDULER scheduler The scheduler.
-- @field #string RQid The radio queue scheduler ID.
-- @field #table queue The queue of transmissions.
-- @field #string alias Name of the radio.
-- @field #number dt Time interval in seconds for checking the radio queue.
-- @field #number delay Time delay before starting the radio queue. 
-- @field #number Tlast Time (abs) when the last transmission finished.
-- @field Core.Point#COORDINATE sendercoord Coordinate from where transmissions are broadcasted.
-- @field #number sendername Name of the sending unit or static.
-- @field #boolean senderinit Set frequency was initialized.
-- @field #number power Power of radio station in Watts. Default 100 W.
-- @field #table numbers Table of number transmission parameters.
-- @field #boolean checking Scheduler is checking the radio queue. 
-- @field #boolean schedonce Call ScheduleOnce instead of normal scheduler.
-- @extends Core.Base#BASE
RADIOQUEUE = {
  ClassName   = "RADIOQUEUE",
  Debug       = nil,
  lid         = nil,
  frequency   = nil,
  modulation  = nil,
  scheduler   = nil,
  RQid        = nil,
  queue       =  {},
  alias       = nil,
  dt          = nil,
  delay       = nil,
  Tlast       = nil,
  sendercoord = nil,
  sendername  = nil,
  senderinit  = nil,
  power       = nil,
  numbers     =  {},
  checking    = nil,
  schedonce   = nil,
}

--- Radio queue transmission data.
-- @type RADIOQUEUE.Transmission
-- @field #string filename Name of the file to be transmitted.
-- @field #string path Path in miz file where the file is located.
-- @field #number duration Duration in seconds.
-- @field #string subtitle Subtitle of the transmission.
-- @field #number subduration Duration of the subtitle being displayed.
-- @field #number Tstarted Mission time (abs) in seconds when the transmission started.
-- @field #boolean isplaying If true, transmission is currently playing.
-- @field #number Tplay Mission time (abs) in seconds when the transmission should be played.
-- @field #number interval Interval in seconds before next transmission.


--- Create a new RADIOQUEUE object for a given radio frequency/modulation.
-- @param #RADIOQUEUE self
-- @param #number frequency The radio frequency in MHz.
-- @param #number modulation (Optional) The radio modulation. Default radio.modulation.AM.
-- @param #string alias (Optional) Name of the radio queue.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:New(frequency, modulation, alias)

  -- Inherit base
  local self=BASE:Inherit(self, BASE:New()) -- #RADIOQUEUE
  
  self.alias=alias or "My Radio"
  
  self.lid=string.format("RADIOQUEUE %s | ", self.alias)
  
  if frequency==nil then
    self:E(self.lid.."ERROR: No frequency specified as first parameter!")
    return nil
  end
  
  -- Frequency in Hz.
  self.frequency=frequency*1000000
  
  -- Modulation.
  self.modulation=modulation or radio.modulation.AM
  
  -- Set radio power.
  self:SetRadioPower()
  
  -- Scheduler.
  self.scheduler=SCHEDULER:New()
  self.scheduler:NoTrace()
  
  return self
end

--- Start the radio queue.
-- @param #RADIOQUEUE self
-- @param #number delay (Optional) Delay in seconds, before the radio queue is started. Default 1 sec.
-- @param #number dt (Optional) Time step in seconds for checking the queue. Default 0.01 sec.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:Start(delay, dt)

  self.delay=delay or 1
  
  self.dt=dt or 0.01
  
  self:I(self.lid..string.format("Starting RADIOQUEUE %s on Frequency %.2f MHz [modulation=%d] in %.1f seconds (dt=%.3f sec)", self.alias, self.frequency/1000000, self.modulation, delay, dt))

  
  if self.schedonce then
    self:_CheckRadioQueueDelayed(self.delta)
  else
    --self.RQid=self.scheduler:Schedule(self, self._CheckRadioQueue, {}, delay, dt)
    self.RQid=self.scheduler:Schedule(nil, RADIOQUEUE._CheckRadioQueue, {self}, delay, dt)
  end
  
  return self
end

--- Stop the radio queue. Stop scheduler and delete queue.
-- @param #RADIOQUEUE self
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:Stop()
  self:I(self.lid.."Stopping RADIOQUEUE.")
  self.scheduler:Stop(self.RQid)
  self.queue={}
  return self
end

--- Set coordinate from where the transmission is broadcasted.
-- @param #RADIOQUEUE self
-- @param Core.Point#COORDINATE coordinate Coordinate of the sender.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:SetSenderCoordinate(coordinate)
  self.sendercoord=coordinate
  return self
end

--- Set name of unit or static from which transmissions are made.
-- @param #RADIOQUEUE self
-- @param #string name Name of the unit or static used for transmissions.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:SetSenderUnitName(name)
  self.sendername=name
  return self
end

--- Set radio power. Note that this only applies if no relay unit is used.
-- @param #RADIOQUEUE self
-- @param #number power Radio power in Watts. Default 100 W.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:SetRadioPower(power)
  self.power=power or 100
  return self
end

--- Set parameters of a digit.
-- @param #RADIOQUEUE self
-- @param #number digit The digit 0-9.
-- @param #string filename The name of the sound file.
-- @param #number duration The duration of the sound file in seconds.
-- @param #string path The directory within the miz file where the sound is located. Default "l10n/DEFAULT/".
-- @param #string subtitle Subtitle of the transmission.
-- @param #number subduration Duration [sec] of the subtitle being displayed. Default 5 sec.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:SetDigit(digit, filename, duration, path, subtitle, subduration)

  local transmission={} --#RADIOQUEUE.Transmission
  transmission.filename=filename
  transmission.duration=duration
  transmission.path=path or "l10n/DEFAULT/"
  transmission.subtitle=nil
  transmission.subduration=nil
  
  -- Convert digit to string in case it is given as a number.
  if type(digit)=="number" then
    digit=tostring(digit)
  end

  -- Set transmission.
  self.numbers[digit]=transmission
  
  return self
end

--- Add a transmission to the radio queue.
-- @param #RADIOQUEUE self
-- @param #RADIOQUEUE.Transmission transmission The transmission data table. 
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:AddTransmission(transmission)
  self:F({transmission=transmission})
  
  -- Init.
  transmission.isplaying=false
  transmission.Tstarted=nil

  -- Add to queue.
  table.insert(self.queue, transmission)
  
  -- Start checking.
  if self.schedonce and not self.checking then
    self:_CheckRadioQueueDelayed()
  end

  return self
end

--- Add a transmission to the radio queue.
-- @param #RADIOQUEUE self
-- @param #string filename Name of the sound file. Usually an ogg or wav file type.
-- @param #number duration Duration in seconds the file lasts.
-- @param #number path Directory path inside the miz file where the sound file is located. Default "l10n/DEFAULT/".
-- @param #number tstart Start time (abs) seconds. Default now.
-- @param #number interval Interval in seconds after the last transmission finished.
-- @param #string subtitle Subtitle of the transmission.
-- @param #number subduration Duration [sec] of the subtitle being displayed. Default 5 sec.
-- @return #RADIOQUEUE self The RADIOQUEUE object.
function RADIOQUEUE:NewTransmission(filename, duration, path, tstart, interval, subtitle, subduration)

  -- Sanity checks.
  if not filename then
    self:E(self.lid.."ERROR: No filename specified.")
    return nil
  end
  if type(filename)~="string" then
    self:E(self.lid.."ERROR: Filename specified is NOT a string.")
    return nil    
  end

  if not duration then
    self:E(self.lid.."ERROR: No duration of transmission specified.")
    return nil
  end
  if type(duration)~="number" then
    self:E(self.lid.."ERROR: Duration specified is NOT a number.")
    return nil    
  end
  

  local transmission={} --#RADIOQUEUE.Transmission
  transmission.filename=filename
  transmission.duration=duration
  transmission.path=path or "l10n/DEFAULT/"
  transmission.Tplay=tstart or timer.getAbsTime()
  transmission.subtitle=subtitle
  transmission.interval=interval or 0
  if transmission.subtitle then
    transmission.subduration=subduration or 5
  else
    transmission.subduration=nil
  end
  
  -- Add transmission to queue.  
  self:AddTransmission(transmission)
  
  return self
end

--- Convert a number (as string) into a radio transmission.
-- E.g. for board number or headings.
-- @param #RADIOQUEUE self
-- @param #string number Number string, e.g. "032" or "183".
-- @param #number delay Delay before transmission in seconds.
-- @param #number interval Interval between the next call.
-- @return #number Duration of the call in seconds.
function RADIOQUEUE:Number2Transmission(number, delay, interval)

  --- Split string into characters.
  local function _split(str)
    local chars={}
    for i=1,#str do
      local c=str:sub(i,i)
      table.insert(chars, c)
    end
    return chars
  end
  
  -- Split string into characters.
  local numbers=_split(number)

  local wait=0    
  for i=1,#numbers do
  
    -- Current number
    local n=numbers[i]
        
    -- Radio call.
    local transmission=UTILS.DeepCopy(self.numbers[n]) --#RADIOQUEUE.Transmission
    
    transmission.Tplay=timer.getAbsTime()+(delay or 0)
    
    if interval and i==1 then
      transmission.interval=interval
    end
    
    self:AddTransmission(transmission)
    
    -- Add up duration of the number.
    wait=wait+transmission.duration
  end
  
  -- Return the total duration of the call.
  return wait
end


--- Broadcast radio message.
-- @param #RADIOQUEUE self
-- @param #RADIOQUEUE.Transmission transmission The transmission.
function RADIOQUEUE:Broadcast(transmission)

  -- Get unit sending the transmission.
  local sender=self:_GetRadioSender()
  
  -- Construct file name.
  local filename=string.format("%s%s", transmission.path, transmission.filename)
  
  if sender then
    
    -- Broadcasting from aircraft. Only players tuned in to the right frequency will see the message.
    self:T(self.lid..string.format("Broadcasting from aircraft %s", sender:GetName()))
    
    
    if not self.senderinit then
    
      -- Command to set the Frequency for the transmission.
      local commandFrequency={
        id="SetFrequency",
        params={
          frequency=self.frequency,  -- Frequency in Hz.
          modulation=self.modulation,
        }}
          
      -- Set commend for frequency
      sender:SetCommand(commandFrequency)
      
      self.senderinit=true
    end
    
    -- Command to tranmit the call.
    local commandTransmit={
      id = "TransmitMessage",
      params = {
        file=filename,
        duration=transmission.subduration,
        subtitle=transmission.subtitle or "",
        loop=false,
      }}    
    
    -- Set command for radio transmission. 
    sender:SetCommand(commandTransmit)
    
    -- Debug message.
    local text=string.format("file=%s, freq=%.2f MHz, duration=%.2f sec, subtitle=%s", filename, self.frequency/1000000, transmission.duration, transmission.subtitle or "")
    MESSAGE:New(text, 2, "RADIOQUEUE "..self.alias):ToAllIf(self.Debug)
      
  else
    
    -- Broadcasting from carrier. No subtitle possible. Need to send messages to players.
    self:T(self.lid..string.format("Broadcasting via trigger.action.radioTransmission()."))
  
    -- Position from where to transmit.
    local vec3=nil
    
    -- Try to get positon from sender unit/static.
    if self.sendername then
      local coord=self:_GetRadioSenderCoord()
      if coord then
        vec3=coord:GetVec3()
      end
    end
    
    -- Try to get fixed positon.
    if self.sendercoord and not vec3 then
      vec3=self.sendercoord:GetVec3()
    end
    
    -- Transmit via trigger.
    if vec3 then
      self:T("Sending")
      self:T( { filename = filename, vec3 = vec3, modulation = self.modulation, frequency = self.frequency, power = self.power } )
      
      -- Trigger transmission.
      trigger.action.radioTransmission(filename, vec3, self.modulation, false, self.frequency, self.power)
      
      -- Debug message.
      local text=string.format("file=%s, freq=%.2f MHz, duration=%.2f sec, subtitle=%s", filename, self.frequency/1000000, transmission.duration, transmission.subtitle or "")
      MESSAGE:New(string.format(text, filename, transmission.duration, transmission.subtitle or ""), 5, "RADIOQUEUE "..self.alias):ToAllIf(self.Debug)
    end

  end
end

--- Start checking the radio queue.
-- @param #RADIOQUEUE self
-- @param #number delay Delay in seconds before checking.
function RADIOQUEUE:_CheckRadioQueueDelayed(delay)
  self.checking=true
  self:ScheduleOnce(delay or self.dt, RADIOQUEUE._CheckRadioQueue, self)
end

--- Check radio queue for transmissions to be broadcasted.
-- @param #RADIOQUEUE self
function RADIOQUEUE:_CheckRadioQueue()
  --env.info("FF check radio queue "..self.alias)

  -- Check if queue is empty.
  if #self.queue==0 then
    -- Queue is now empty. Nothing to else to do.
    self.checking=false
    return
  end

  -- Get current abs time.
  local time=timer.getAbsTime()
  
  local playing=false
  local next=nil  --#RADIOQUEUE.Transmission
  local remove=nil
  for i,_transmission in ipairs(self.queue) do
    local transmission=_transmission  --#RADIOQUEUE.Transmission
    
    -- Check if transmission time has passed.
    if time>=transmission.Tplay then 
      
      -- Check if transmission is currently playing.
      if transmission.isplaying then
      
        -- Check if transmission is finished.
        if time>=transmission.Tstarted+transmission.duration then
          
          -- Transmission over.
          transmission.isplaying=false
          
          -- Remove ith element in queue.
          remove=i
          
          -- Store time last transmission finished.
          self.Tlast=time
                    
        else -- still playing
        
          -- Transmission is still playing.
          playing=true
          
        end
      
      else -- not playing yet
      
        local Tlast=self.Tlast
      
        if transmission.interval==nil  then
      
          -- Not playing ==> this will be next.
          if next==nil then
            next=transmission
          end
          
        else
        
          if Tlast==nil or time-Tlast>=transmission.interval then
            next=transmission            
          else
            
          end
        end
        
        -- We got a transmission or one with an interval that is not due yet. No need for anything else.
        if next or Tlast then
          break
        end
             
      end
      
    else
      
        -- Transmission not due yet.
      
    end  
  end
  
  -- Found a new transmission.
  if next~=nil and not playing then
    self:Broadcast(next)
    next.isplaying=true
    next.Tstarted=time
  end
  
  -- Remove completed calls from queue.
  if remove then
    table.remove(self.queue, remove)
  end
  
  -- Check queue.
  if self.schedonce then
    self:_CheckRadioQueueDelayed()
  end
  
end

--- Get unit from which we want to transmit a radio message. This has to be an aircraft for subtitles to work.
-- @param #RADIOQUEUE self
-- @return Wrapper.Unit#UNIT Sending aircraft unit or nil if was not setup, is not an aircraft or is not alive.
function RADIOQUEUE:_GetRadioSender()

  -- Check if we have a sending aircraft.
  local sender=nil  --Wrapper.Unit#UNIT

  -- Try the general default.
  if self.sendername then
    -- First try to find a unit 
    sender=UNIT:FindByName(self.sendername)

    -- Check that sender is alive and an aircraft.
    if sender and sender:IsAlive() and sender:IsAir() then
      return sender
    end
    
  end
    
  return nil
end

--- Get unit from which we want to transmit a radio message. This has to be an aircraft for subtitles to work.
-- @param #RADIOQUEUE self
-- @return Core.Point#COORDINATE Coordinate of the sender unit.
function RADIOQUEUE:_GetRadioSenderCoord()

  local vec3=nil

  -- Try the general default.
  if self.sendername then
  
    -- First try to find a unit 
    local sender=UNIT:FindByName(self.sendername)

    -- Check that sender is alive and an aircraft.
    if sender and sender:IsAlive() then
      return sender:GetCoordinate()
    end
    
    -- Now try a static. 
    local sender=STATIC:FindByName( self.sendername, false )

    -- Check that sender is alive and an aircraft.
    if sender then
      return sender:GetCoordinate()
    end
    
  end
    
  return nil
end
