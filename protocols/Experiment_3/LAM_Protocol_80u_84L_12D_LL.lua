--------------------------------------------------
--*** LAM helper functions START ***
--------------------------------------------------

scriptRunTimeStart = get_experiment_time()/1000 -- script will be stopped & resumed if scriptRunTime = get_experiment_time()/1000 - scriptRunTimeStart exceeds scriptRunTimeMax

-- add debug comments to *.log file?
writeDbgComments = false --for use in add_dbg_comment(comment, writeDbgComments)

-- interpolation settings
dtMin = 0.25 --interpolation stepwidth (seconds) [tbd. depending on timestamp precision and execution time of one full "set LED power & PWM frequency" loop]
--set_lam_relative_powers(), set_lam_workmode() and set_lam_frequency() take approx. 0.2s each. Simultaneous change of all 3 parameters is unusual, therefore 0.25s should work.
nStepMax = 1000 --not more than 1000 additional interpolation setpoints allowed between two regular setoints. should be enough for quasi-continuous LED power change

scriptRunTimeMax = 9.5 --workaround 2022-12 until HMI bug that causes lua script error is fixed. With runTimeMax = 2e6 LAM freezes after ~4min
-- scriptRunTimeMax = 2592000 --seconds. Script will be stopped/interrupted (and re-started by the HMI) if scriptRunTimeMax is exceeded.
-- for an uninterrupted script execution this value should be set to >max(setTimes), e.g. 1 month: 30*24*60*60 = 2592000
-- default: 10 (max lua sript run time was limited to 10s <HMI 1.7.4). 
-- !!!!! scriptRunTimeMax is set to 9.5s if repeatType == 3 further down in the code !!!!
scriptRunTime = get_experiment_time()/1000 - scriptRunTimeStart --actual run time in seconds. if > scriptRunTimeMax script execution will be interrupted
lastCycle = 1

if not script_ever_ran then

--define helper functions:

---rounds a non-integer number
---@param input_number number non-integer number
function round_number(input_number)
--rounded_number = tonumber(string.format("%f", input_number))
local rounded_number = math.floor(input_number+0.5)
return rounded_number
end


--!!! not needed if all(setType==0) !!!
---function that calculates the interpolated value (e.g. LED power/frequency) for the given interpolation method and get_experiment_time()/1000 between two setpoints N and N+1.
---@param interpType string interpolation method between the two setpoints: "lin" "sin1/2" "exp1/2" "log1/2". "step" 
---@param t number t-t(N) elapsed get_experiment_time()/1000 since the last setpoint N in seconds. can also be an array, but in this case, function output will also be an array.
---@param dTime number t(N+1)-t(N) in seconds
---@param v1 number value(N)
---@param v2 number value(N+1)
function LAM_setpoints_interp(interpType, t, dTime, v1, v2)
local nTime = #t
local interpVal = {}
local dv = v2-v1
local expSpan = 5 --slope of the exp/log interpolation
local dexp = math.exp(expSpan)-math.exp(0)
local interpolateSetpoint = 1
local pi = 3.141592653589793

if interpType == "lin" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv*t[index]/dTime
end
elseif interpType == "sin1" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv*math.sin(pi/2*t[index]/dTime)
end
elseif interpType == "sin2" then
for index, value in pairs(t) do
--interpVal[index] = v1 + dv*math.sin(pi/2*(1+t[index]/dTime))
interpVal[index] = v2 - dv*math.sin(pi/2*(1+t[index]/dTime))
end
elseif interpType == "sin3" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv*0.5*(1+math.sin(pi*(t[index]/dTime-0.5)))
end
elseif interpType == "exp1" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv* (math.exp((t[index])/dTime * expSpan)-math.exp(0))/dexp
end
elseif interpType == "exp2" then
for index, value in pairs(t) do
--interpVal[index] = v1 + dv*(math.exp(-(t[index])/dTime * expSpan) - math.exp(-expSpan)) * 1/(math.exp(0)-math.exp(-expSpan))
interpVal[index] = v2 - dv*(math.exp(-(t[index])/dTime * expSpan) - math.exp(-expSpan)) * 1/(math.exp(0)-math.exp(-expSpan))
end
elseif interpType == "log1" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv*math.log( 1+(t[index])/dTime * (math.exp(expSpan)-1)) / expSpan
end
elseif interpType == "log2" then
for index, value in pairs(t) do
interpVal[index] = v1 + dv*(1-(math.log(1+(1-(t[index])/dTime) * (math.exp(expSpan)-1)) / expSpan))
end
else
comment = ("LAM_setpoints_interp: unknown interpType " .. interpType .. " -> no interpolation")
add_comment(comment)
for index, value in pairs(t) do
interpVal[index] = v1
end
interpolateSetpoint = 0
--interpType = "step"
end
return interpVal, interpolateSetpoint
--interpVal, interpolateSetpoint = LAM_setpoints_interp(interpType, t, dTime, v1, v2)
end


---Add a comment to the experiment file. Additional input for simple deactivation of additional comments used for debugging
---@param comment string
---@param writeComment boolean
function add_dbg_comment(comment, writeComment) 
if writeComment == true then
add_comment(comment)
else
--writeComment == 0 -> do not write comment
end
end

comment = string.format("LAM: helper functions initialized @ %fs", get_experiment_time()/1000)
add_comment(comment)


end -- if not script_ever_ran
--------------------------------------------------
--*** LAM helper functions END ***
--------------------------------------------------


-- initialize only if not initialized yet:
if scriptStopped == nil then
scriptStopped = -1
end
if scriptResume == nil then
scriptResume = -1
end

-- ***** define setpoint values *****
if (not script_ever_ran) then

-- *****LAM_PROTOCOL_START*****
--LAMProtocol.lam={protocol_name='LAM_Protocol_80u_84L_12D_LL';;LAM_name='LAM_PT01';;channel_group={1;2;3;4;5;6;7;7;7;8;8;9;10;11;11;12;13;14;15;16};;calibration_group={{1 6 9 14} {2 10 15} {3 11 16} {4 12} {5 13} {7} {8 }};;max_current={0.71;0.71;0.50;0.50;0.71;0.71;0.71;0.71;0.71;0.71;0.71;0.71;0.71;0.60;0.60;0.71;0.71;0.71;0.71;0.71};;group_name={'365nm';'385nm';'405nm';'420nm';'450nm';'470nm';'520nm';'590nm';'620nm';'660nm';'690nm';'730nm';'750nm';'780nm';'820nm';'850nm'};;repeat=0;;name='LAM_Protocol_80u_96L_12D_96L';;t;pwr;freq;type;;0;0 0 0 0 2.300000e+00 0 3.800000e+00 1.900000e+00 2.600000e+00 2.100000e+00 2.200000e+00 2.100000e+00 0 0 0 0;7000;0;;302400;0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0;0;0;;345600;0 0 0 0 2.300000e+00 0 3.800000e+00 1.900000e+00 2.600000e+00 2.100000e+00 2.200000e+00 2.100000e+00 0 0 0 0;7000;0;;}
setTimes={0.00,302400.00,345600.00}
setType={0,0,0}
setPower={{0.00,0.00,0.00,0.00,2.30,0.00,3.80,1.90,2.60,2.10,2.20,2.10,0.00,0.00,0.00,0.00};
{0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00};
{0.00,0.00,0.00,0.00,2.30,0.00,3.80,1.90,2.60,2.10,2.20,2.10,0.00,0.00,0.00,0.00}}
setFrequency={7000.0,0.0,7000.0}
repeatType=0
-- *****LAM_PROTOCOL_END*****


-- add additional setpoint at t=0 if it does not exist AND interpolation type of first setpoint is not step:
if setTimes[1] > 0 and setType[1] > 0 then

comment = string.format("LAM: adding additional setpoint @t=0s: first setpoint (@%1.2fs) interp type is [%i]", setTimes[1], setType[1])
add_comment(comment)

-- add setpoint 0 | 0:
table.insert(setTimes, 1, 0)
table.insert(setType, 1, 0)
table.insert(setPower, 1, {}) --table.insert(setPower, 1, setPower[1]) somehow couples setPower[1] & setPower[2]
for iCh = 1, #setPower[2] do --caution: #setPower[1]==0
setPower[1][iCh] = 0;
end
table.insert(setFrequency, 1, 0)

end

n_setpoints=#setTimes
n_channels =#setPower[1]

interpolateSetpoints = 0 --set to 1 if any interpolation is performed

--the following for-loop is not needed if all(setType==0)
setTimesInterp = {}
setTypeInterp = {}
setPowerInterp = {}
setFrequencyInterp = {}
isInterpolatedSetpoint={}

tInterpStart = get_experiment_time()/1000
for index, value in pairs(setType) do

interpolateSetpoint = 0 --set to 1 if conditions are met

if index < n_setpoints and setType[index+1] > 0 then
--next setpoint set type is not step

--TDO: implement channel-specific setpoint types if #setType[index+1] > 1

--TDO: implement frequency interpolation if not (setFrequency[index] == setFrequency[index+1])
--PWM frequency should not change if setType[index+1] > 0
stepFrequencyMatch = setFrequency[index] == setFrequency[index+1]
--warning comment
if not stepFrequencyMatch then
comment = ("LAM notification: PWM frequency changes between interpolated setpoints [setpoints " ..  tostring(index) .. " " .. tostring(index+1) .."] --frequency will not be interpolated!--" )
add_comment(comment)
end

--check if time between setTime[index] and setTime[index+1] is sufficient for interpolation:
local dt = setTimes[index+1] - setTimes[index]
local dPowerMax = 0
for iCh = 1, n_channels do
if math.abs(setPower[index][iCh] - setPower[index+1][iCh]) > dPowerMax then
dPowerMax = math.abs(setPower[index][iCh] - setPower[index+1][iCh])
end
end


if dt > dtMin*2 and dPowerMax > 0 then--at least one additional setpoint will be created: do interpolation

interpolateSetpoint = 1
--round number of interpolation steps
-- nStep = tonumber(string.format("%f", dt/dtMin))
nStep = round_number(dt/dtMin)

local pwrStepMin = 0.02;
-- check if interpolation (assumed as linear) pwr stepwidth with nStep is >pwrStepMin, otherwise the number of interpolation points can be reduced further
if dPowerMax/nStep < pwrStepMin then
nStep = round_number(dPowerMax / pwrStepMin);
end

if nStep > nStepMax then
comment = ("LAM: number of interpolation points reduced from " .. tostring(nStep) .. " to " .. tostring(nStepMax))
add_comment(comment)
nStep = nStepMax
end
dtStep = dt/nStep

if dPowerMax/nStep > 2*pwrStepMin then --dt between the interpolated setpoints is too short for smooth interpolation
comment = ("LAM: dt between the interpolated setpoints is too low for smooth interpolation. LED power stepwidth is " .. tostring(dPowerMax/nStep) .. "% ")
add_comment(comment)
end

interpTime = {} --0:dtStep:
for iTime = 0, nStep do
interpTime[iTime+1] = 0 + iTime * dtStep
end

--different interpolation methods
if setType[index+1] == 1 then
interpType = "lin"
elseif setType[index+1] == 2 then
interpType = "sin1" --sin(0:pi/2)
elseif setType[index+1] == 3 then
interpType = "sin2" --sin(pi/2:pi)
elseif setType[index+1] == 4 then
interpType = "sin3" --sin(pi/2:pi)
elseif setType[index+1] == 5 then
interpType = "exp1"
elseif setType[index+1] == 6 then
interpType = "exp2"
elseif setType[index+1] == 7 then
interpType = "log1"
elseif setType[index+1] == 8 then
interpType = "log2"
else
comment = ("LAM: unknown setType " .. tostring(setType[index+1]) .. " --no interpolation--")
add_comment(comment)
interpolateSetpoint = 0 --cannot perform interpolation with unknown method
end

--interpVal, interpolateSetpoint = LAM_setpoints_interp(interpType, t, dTime, v1, v2)
if interpolateSetpoint == 1 then

interpolateSetpoints = 1 --set to 1 if any(setType>0)
setTimesInterpInd = #setTimesInterp

--init
--for iTime = 0, nStep do
--    setPowerInterp[setTimesInterpInd+iTime+1] = setPower[1]
--end

for iCh = 1, n_channels do

interpVal = LAM_setpoints_interp(interpType, interpTime, dt, setPower[index][iCh], setPower[index+1][iCh])
numInterpVal = #interpVal -- == nStep, for debugging

--for iTime = 0, nStep do
--    setPowerInterp[setTimesInterpInd+iTime+1] = setPower[1]
--end
for iTime = 0, nStep-1 do --interpTime[nStep+1] = setTimes[index+1]: nStep-1 to avoid duplicates
--setTimesInterp only on the first iCh run
if iCh == 1 then
isInterpolatedSetpoint[setTimesInterpInd+iTime+1] = true;
setTimesInterp[setTimesInterpInd+iTime+1] = interpTime[iTime+1] + setTimes[index]--iTime starts at 0 -> use iTime+1
setTypeInterp[setTimesInterpInd+iTime+1] = 0 --set to "step"
setFrequencyInterp[setTimesInterpInd+iTime+1] = setFrequency[index] --no interpolation (yet)
setPowerInterp[setTimesInterpInd+iTime+1] = {} --initialize DO NOT USE =setPower[1] or strange things will happen                                
end
setPowerInterp[setTimesInterpInd+iTime+1][iCh] = interpVal[iTime+1]
end
isInterpolatedSetpoint[setTimesInterpInd+1] = false -- first value is the original setpoint

end

comment = ("LAM: ".. tostring(nStep) .. " interpolation points added at setpoint " .. tostring(index) .. " [type: " .. interpType .. "]")
add_comment(comment)

else --not(interpolateSetpoint == 1) -> step: no interpolation -> set XXXInterp = XXX[index]: condition: interpolateSetpoint == 0

print("interpolateSetpoint: " .. tostring(interpolateSetpoint))

end


else --no interpolation due to short timespan between setpoints -> set XXXInterp = XXX[index]: condition: interpolateSetpoint == 0

comment = ("LAM notification: not sufficient time between setpoints to perform [type" .. interpType .. "] interpolation [setpoints " ..  tostring(index) .. "<->" .. tostring(index+1) .." | dt=" .. tostring(dt) .. "s]")
add_comment(comment)
interpolateSetpoint = 0
interpType = "step"

end

else -- index == n_setpoints: last setpoint is not included in interpolated data
--  or setType[index+1] > 0: step
---> set XXXInterp = XXX[index]: condition: interpolateSetpoint == 0

-- print("interpolateSetpoint: " ..tostring(interpolateSetpoint))

end --index < n_setpoints and setType[index+1] > 0 then

if interpolateSetpoint == 0 then --possible causes: unknown interpolation method, dt too short, last setpoint
--no interpolation
setTimesInterpInd = #setTimesInterp
isInterpolatedSetpoint[setTimesInterpInd+1] = false
setTimesInterp[setTimesInterpInd+1] = setTimes[index]
setTypeInterp[setTimesInterpInd+1] = setType[index] --should be 0 (== "step")
setFrequencyInterp[setTimesInterpInd+1] = setFrequency[index] --no interpolation (yet)
setPowerInterp[setTimesInterpInd+1] = {} --setPower[1] produces strange results and somehow couples setPowerInterp<->setPower so that changing a value in setPowerInterp also changes setPower
for iCh = 1, n_channels do
setPowerInterp[setTimesInterpInd+1][iCh] = setPower[index][iCh]
end
end

end --index, value in pairs(setType) do    
tInterpEnd = get_experiment_time()/1000

if not (#setTimesInterp == #setTimes) then --additional condition interpolateSetpoints == 1 redundant
-- overwrite original setpoints:

numelInterpSetpoints = #setTimesInterp - #setTimes

setTimesBackup = setTimes
setTypeBackup = setType
setFrequencyBackup = setFrequency
setPowerInterpBackup = setPower

setTimes = setTimesInterp
setType = setTypeInterp
setFrequency = setFrequencyInterp
setPower = setPowerInterp

n_setpoints = #setTimes

comment = string.format("LAM: added %1.0f interpolated setpoints: tStart|tEnd|dt: %1.4f|%1.4f|%1.4f", numelInterpSetpoints, tInterpStart, tInterpEnd, tInterpEnd-tInterpStart)
add_comment(comment)

end

comment = ("LAM: Script started [" .. tostring(scriptRunTimeStart) .. "s] | number of setpoints [" .. tostring(n_setpoints) .. "]")
add_comment(comment)

end -- if (not script_ever_ran) then


if (not script_ever_ran) or (scriptResume == 0 and not repeatType == 0) then
--scriptResume ~ matching repeatType condition: is set after first script run and has therefore not do be defined before

if script_ever_ran then
scriptRunNo = scriptRunNo + 1
else
scriptRunNo = 1
end

-- initialize setpoint index:
iTStart = 1 --if script was interrupted this value is set to the first un-set setpoint (if no forced restart because of repeatType 1|2 is required: then iTStart = 1 is set)
scriptStopped = 0 --was script interrupted during last execution to pre-empt automatic time-out script termination by the HMI    

--check for any setpoints with setType>0 and add additional interpolation setpoints:

startTimeSec = get_experiment_time()/1000


else --script_ever_ran = true and scriptResume == 1

scriptRunNo = scriptRunNo + 1

end

-- initialize LAM
if (not script_ever_ran) then --no intialization if script is resumed!

-- set_lam_leds_onoff(0) -- tbd
set_lam_workmode("DC")
set_lam_frequency(0)

actualFrequency = 0
actualWorkMode = "DC"
actualPower = {} -- was setPower[1] but this couples actualPower <-> setPower[1]

--power off
for index, value in pairs(setPower[1]) do
-- set_lam_relative_power(index, 0)
actualPower[index] = 0
end
set_lam_relative_powers(actualPower)

comment = string.format("LAM: initialized: all LEDs set to 0%% [%1.1fs]", get_experiment_time()/1000-scriptRunTimeStart)
add_comment(comment)

end

-- modify hard-coded scriptRunTimeMax value (~1 month in seconds) if repeatType == 2 (since "cycle" is only updated updated once per lua script execution when the script is started) 
if (not script_ever_ran) and repeatType == 2 then
-- 0:repeatOff 1:repeatFilter 2:repeatCycle 3:repeatForever
scriptRunTimeMax = 9.5;
-- HMI attemps to re-start lua script every 10s (if it is not still running). 0.5s buffer should be sufficient.
end

--scriptRunTimeMax=50 script_ever_ran=true cycle=2 scriptRunNo=5 iTStart=116 repeatType=0 scriptResume=1 scriptStopped=1
iT = iTStart

comment = string.format("LAM: script main loop started: script_ever_ran=%s | scriptRunNo=%i | cycle=%i | scriptRunNo=%i | iTStart=%i(%i) | repeatType=%i | scriptResume=%i | scriptStopped=%i | scriptStartTime=%1.2fs | expTime=%1.2fs",  script_ever_ran, scriptRunNo, cycle, scriptRunNo, iTStart, n_setpoints, repeatType, scriptResume, scriptStopped, startTimeSec, get_experiment_time()/1000)
add_comment(comment)

while iT <= n_setpoints do

tSec = get_experiment_time()/1000 - startTimeSec -- time in sec

lastCycle = cycle; --cycle is only updated once when the script is started :-(

filter = '1' --TDO: remove repeat option "filter"
lastFilter = filter

if tSec >= setTimes[iT] then --new setpoint

if isInterpolatedSetpoint[iT] == false or writeDbgComments == true then
comment = string.format("LAM: setpoint %i(%i) @ %1.2fs [target: %1.2fs | expTime: %1.2fs]", iT, n_setpoints, tSec, setTimes[iT], get_experiment_time()/1000)
add_comment(comment)
end

--set LED power & PWM frequency (only if the value/work mode has changed)                

-- set LED power
changeLEDPower = false
for i = 1, #setPower[iT] do
if not (actualPower[i] == setPower[iT][i]) then
changeLEDPower = true
actualPower[i] = setPower[iT][i];
end
end
if changeLEDPower == true then

t0 = get_experiment_time()/1000
set_lam_relative_powers(setPower[iT])
t1 = get_experiment_time()/1000

s = ''
for i = 1, #actualPower do
s = (string.format("%s %1.1f ", s, actualPower[i]))
end
if isInterpolatedSetpoint[iT] == false or writeDbgComments == true then
comment = string.format("LAM: LAM Channels set to [ %s]%% | [%1.2fs]", s, t1-t0)
add_comment(comment)
end
else
if isInterpolatedSetpoint[iT] == false or writeDbgComments == true then
comment = string.format("LAM: new setpoint but no LED power change detected")
add_comment(comment)
end
end

-- for index, value in pairs(setPower[iT]) do		
--     set_lam_relative_power(index, value)			
--     comment = ("LAM: set LED Power for Channel " ..  tostring(index) .. " to " .. tostring(value) .."% @ Time " .. tostring(tSec) .. "s [target: " .. tostring(setTimes[iT]) .. "s]")
--     add_comment(comment)
-- end

-- LAM initialized with actualFrequency = 0 actualWorkMode = "DC"

-- detect and set work mode
if setFrequency[iT] > 0 then
LAMWorkMode = "PWM"
else
LAMWorkMode = "DC"
end
if not (actualWorkMode == LAMWorkMode) then

t0 = get_experiment_time()/1000;
set_lam_workmode(LAMWorkMode)
actualWorkMode = LAMWorkMode
t1 = get_experiment_time()/1000;

comment = string.format("LAM: LAM work mode set to [ %s] | [%1.2fs]", actualWorkMode, t1-t0)
add_comment(comment);

end

-- set PWM frequency
if not (actualFrequency == setFrequency[iT]) then

t0 = get_experiment_time()/1000;
set_lam_frequency(setFrequency[iT])
actualFrequency = setFrequency[iT]
t1 = get_experiment_time()/1000;

comment = string.format("LAM: LAM frequency set to set to %1.0fHz | [%1.2fs]", actualFrequency, t1-t0)
add_comment(comment);

end

--activate LAM on first run
if iT == 1 then
-- set_lam_leds_onoff(1) --function not yet implemented
end

--next setpoint:
iT = iT+1

end --tSec >= setTimes[iT]

-- check if any of the criteria for stopping or re-starting the script are met:
-- 1) scriptRunTime > scriptRunTimeMax and stop execution if time is exceeded
--    (even if the condition iT <= n_setpoints is still fulfilled)
-- for iT > n_setpoints the script will stop anyway and no action is needed
scriptRunTime = get_experiment_time()/1000 - scriptRunTimeStart
scriptStopped = 0 --set to 1 if script will be stopped

-- stop/restart/resume script/while-loop?
-- reminder: iT = iT+1 is set after setpoint(iT) values are set -> if iT>n_setpoints: all setpoints were already set.
-- repeatType 0:repeatOff 1:repeatFilter 2:repeatCycle 3:repeatForever

if (repeatType == 1 and (not filter == lastFilter)) or (repeatType == 2 and cycle > lastCycle) then
--repeatType 1&2 can trigger a re-start of the script regardless of time & setpoint:

if iT <= n_setpoints then
if repeatType == 1 and (not filter == lastFilter) then
comment = ("LAM: script stopped at setpoint " .. tostring(iT) .. "(" .. tostring(n_setpoints) .. "): new filter (new: " .. tostring(filter) .. " | old: " .. tostring(lastFilter) .. ")" )
elseif (repeatType == 2 and cycle > lastCycle) then
comment = ("LAM: script stopped at setpoint " .. tostring(iT) .. "(" .. tostring(n_setpoints) .. "): new cycle started (#" .. tostring(cycle) .. ")")
end
add_comment(comment)
end

if scriptRunTime >= scriptRunTimeMax then
-- stop the script before the HMI kills it.
-- start the next script run with iTStart = 1

iT = n_setpoints + 1 --stops execution of while-loop
scriptStopped = 1
scriptResume = 0
iTStart = 1

comment = ("LAM: repeatType [" .. tostring(repeatType) .. "]  && scriptRunTime >= scriptRunTimeMax: script will be run again")
add_dbg_comment(comment, writeDbgComments)

else
-- time left for a while-loop re-start
iT = 1 -- will re-start the while-loop
scriptStopped = 0
scriptResume = 0
iTStart = 1

comment = ("LAM: repeatType [" .. tostring(repeatType) .. "]  && scriptRunTime < scriptRunTimeMax: iT set to 1")
add_dbg_comment(comment, writeDbgComments)

end

elseif scriptRunTime >= scriptRunTimeMax then
-- max allowed script execution time exceeded -> stop script before the HMI kills it.
-- re-starting conditions for repeatType 1,2 are checked in the first if statement and do not have to be re-checked here
-- -> only repeatType 0 3 expected

if iT <= n_setpoints then
--script will be stopped before the last setpoint is reached. the script will be re-started by the HMI and continue with the remaining setpoints starting with iT

iTStart = iT;

iT = n_setpoints + 1 --stops execution of while-loop
scriptStopped = 1
scriptResume = 1

comment = ("LAM: scriptRunTimeMax(" ..tostring(scriptRunTimeMax) .."s) exceeded: script stopped at setpoint " .. tostring(iTStart-1) .. 
"(" .. tostring(n_setpoints) .. ") @ " .. tostring(scriptRunTime) .."s: scriptResume=" .. tostring(scriptResume))
add_comment(comment)


else -- iT > n_setpoints: all setpoints were set. a rare coincidence when scriptRunTime is just > scriptRunTimeMax.
-- normally this will happen at scriptRunTime <= scriptRunTimeMax
-- while loop breaking condition automatically fulfilled: iT > n_setpoints by definition

scriptStopped = 0 -- all setpoints were set

if repeatType == 0 then -- repeat off

scriptResume = 0
iTStart = n_setpoints + 1
run_again = false -- lua script will not be called again during current protocol run

comment = ("LAM: scriptRunTime < scriptRunTimeMax, all setpoints set and repeatType 0 -> setting run_again = false")
add_dbg_comment(comment, writeDbgComments)

elseif repeatType == 3 then -- repeat forever -> start next run at first setpoint

scriptResume = 0
iTStart = 1

comment = ("LAM: scriptRunTime < scriptRunTimeMax, all setpoints set and repeatType 3. script will be called again and start with first setpoint")
add_dbg_comment(comment, writeDbgComments)

else
comment = ("LAM: unexpected repeat type [" .. tostring(repeatType) .. " -> check case definition")
add_comment(comment)
end

end

elseif iT > n_setpoints then -- all setpoints set but NOT scriptRunTime >= scriptRunTimeMax
-- iT > n_setpoints will break the while-loop automatically

if repeatType == 0 then -- repeat off
--last setpoint set, but scriptRunTime < scriptRunTimeMax.
scriptStopped = 1
scriptResume = 0
iTStart = n_setpoints + 1
run_again = false -- lua script will not be called again during current protocol run

comment = ("LAM: all setpoints set and repeatType 0 -> stopping script and setting run_again = false")
add_dbg_comment(comment, writeDbgComments)

elseif repeatType == 3 then -- repeat forever -> restart directly
-- while-loop stopping condition fulfilled BUT scriptRunTime < scriptRunTimeMax and repeatType == 3 "forever"
-- -> setting iT to 1 will restart the while-loop: wait until scriptRunTime > scriptRunTimeMax takes up to scriptRunTimeMax if script was just re-started
scriptStopped = 0
scriptResume = 1
iTStart = 1
iT = 1

startTimeSec = get_experiment_time()/1000 -- re-start script timer

comment = ("LAM: all setpoints set and repeatType [3] -> re-starting script")
add_dbg_comment(comment, writeDbgComments)

end

else -- iT <= n_setpoints and scriptRunTime < scriptRunTimeMax  and (repeatType == 1 and (filter == lastFilter))) and (repeatType == 2 and cycle == lastCycle)
-- do nothing and repeat while-loop until tSec >= setTimes[iT] or any other condition is met
-- if script is stopped by the MHI due to timeout: resume script
iTStart = iT;
scriptResume = 1
scriptStopped = 0

end


end --while iT <= n_setpoints do
