-- CONVERTIR A UTF-16LE USANDO NOTEPAD++ PARA QUE MUESTRE LOS SIMBOLOS Y ACENTOS CORRECTAMENTE 
function Initialize()
    lang = SKIN:GetVariable('lang')
    -- Initialize table to store last used phrases and timestamps
    lastUsedPhrases = {}
    rotationCooldown = 300  -- 5 minutes in seconds (adjust as needed)
    
    -- Debug control - set to false to disable spammy logs
    debugMode = false  -- Set to true only when troubleshooting
    
    -- Track last values to avoid log spam
    lastCondition = ""
    lastIconCode = ""
    lastTemperature = nil
end

function Update()
    local phrases = {}
    local phrasesFile = nil
    local phrasesPath = SKIN:GetVariable('@') .. 'phrases_' .. lang .. '.lua'

    -- Intentar cargar el archivo de frases
    local success, result = pcall(dofile, phrasesPath)
    
    if not success then
        SKIN:Bang('!Log', 'Error al cargar el archivo: ' .. phrasesPath .. '. Error: ' .. tostring(result), 'Error')
        return
    end

    -- Asegúrese de que la función GetPhrase esté disponible y llámela
    if result and result.GetPhrase then
        phrases = result.GetPhrase().phrases
    else
        SKIN:Bang('!Log', 'La función GetPhrase no encontrada en el archivo', 'Error')
        return
    end

    if #phrases == 0 then
        SKIN:Bang('!Log', 'No se cargaron frases', 'Error')
        return "No se cargaron frases"
    end

    -- Get weather data from Description measure
    local weatherCondition = string.lower(SKIN:GetMeasure('Description'):GetStringValue() or "")
    
    -- Get icon code from Icon measure
    local iconCode = string.lower(SKIN:GetMeasure('Icon'):GetStringValue() or "")
    
    -- Only log weather changes, not every cycle
    if debugMode and weatherCondition ~= lastCondition then
        SKIN:Bang('!Log', 'Weather description: "' .. weatherCondition .. '"', 'Debug')
        lastCondition = weatherCondition
    end
    
    -- Only log icon changes
    if debugMode and iconCode ~= lastIconCode then
        SKIN:Bang('!Log', 'Icon code: "' .. iconCode .. '"', 'Debug')
        lastIconCode = iconCode
    end
    
    -- Get temperature (try multiple possible measure names)
    local temperature = nil
    local tempMeasure = SKIN:GetMeasure('TempRounded') or SKIN:GetMeasure('Temp') or SKIN:GetMeasure('RoundTemp')
    if tempMeasure then
        local tempValue = tempMeasure:GetStringValue()
        if tempValue and tempValue ~= "" then
            temperature = tonumber(tempValue)
        end
    end
    
    -- Only log temperature changes
    if debugMode and temperature ~= lastTemperature then
        if temperature then
            SKIN:Bang('!Log', 'Current temperature: ' .. temperature .. '°C', 'Debug')
        else
            SKIN:Bang('!Log', 'Could not get temperature value', 'Debug')
        end
        lastTemperature = temperature
    end

    local found = false
    local phrase = {}

    -- Collect all matching phrases for current weather, icon, and temperature
    local matchingPhrases = {}
    for _, p in ipairs(phrases) do
        -- Check condition/icon match
        local conditionMatch = false

        if p.condition and p.icon then
            -- Both condition and icon specified: require both to match
            conditionMatch = (string.lower(p.condition) == weatherCondition) and
                             (string.lower(p.icon) == iconCode)
        elseif p.condition then
            -- Only condition specified
            conditionMatch = (string.lower(p.condition) == weatherCondition)
        elseif p.icon then
            -- Only icon specified
            conditionMatch = (string.lower(p.icon) == iconCode)
        else
            -- No condition or icon: temperature-only phrase
            conditionMatch = true
        end
        
        -- Check temperature range if condition matches
        if conditionMatch then
            local tempMatch = true
            
            -- Check min temperature if specified
            if p.min ~= nil and temperature ~= nil then
                tempMatch = tempMatch and (temperature >= p.min)
            end
            
            -- Check max temperature if specified
            if p.max ~= nil and temperature ~= nil then
                tempMatch = tempMatch and (temperature <= p.max)
            end
            
            -- If no temperature data available but phrase requires it, skip
            if temperature == nil and (p.min ~= nil or p.max ~= nil) then
                tempMatch = false
            end
            
            if tempMatch then
                table.insert(matchingPhrases, p)
                -- Only log found phrases in debug mode
                if debugMode then
                    SKIN:Bang('!Log', 'Found matching phrase: ' .. p.title, 'Debug')
                end
            end
        end
    end

    if #matchingPhrases > 0 then
        -- Create a unique key combining condition, icon, and temperature range for tracking
        local conditionKey = weatherCondition .. "_" .. iconCode
        if temperature then
            -- Round temperature to nearest 5 degrees for grouping
            local tempGroup = math.floor(temperature / 5) * 5
            conditionKey = conditionKey .. "_" .. tempGroup
        end
        
        -- Initialize tracking for this condition/icon/temperature group if not exists
        if not lastUsedPhrases[conditionKey] then
            lastUsedPhrases[conditionKey] = {
                index = 0,
                lastUpdate = 0,
                availablePhrases = {}
            }
        end
        
        local tracker = lastUsedPhrases[conditionKey]
        local currentTime = os.time()
        
        -- Check if we need to rotate: cooldown passed OR stored index invalid (phrase no longer matches)
        local needRotation = (tracker.lastUpdate == 0) or 
                             ((currentTime - tracker.lastUpdate) >= rotationCooldown) or
                             (tracker.index == 0) or
                             (tracker.index > #matchingPhrases) or
                             (matchingPhrases[tracker.index] == nil)
        
        if needRotation then
            -- Rebuild available phrases if empty
            if #tracker.availablePhrases == 0 then
                for i = 1, #matchingPhrases do
                    table.insert(tracker.availablePhrases, i)
                end
            end
            
            if #tracker.availablePhrases > 0 then
                local randomPos = math.random(1, #tracker.availablePhrases)
                local selectedIndex = tracker.availablePhrases[randomPos]
                table.remove(tracker.availablePhrases, randomPos)
                
                phrase = matchingPhrases[selectedIndex]
                tracker.index = selectedIndex
                tracker.lastUpdate = currentTime
                found = true
                
                -- Only log selection in debug mode
                if debugMode then
                    SKIN:Bang('!Log', 'Selected phrase ' .. selectedIndex .. ' for condition: ' .. weatherCondition .. ' / icon: ' .. iconCode .. ' at temp: ' .. tostring(temperature), 'Debug')
                end
            end
        else
            -- Cooldown not passed and stored index is valid → keep using current phrase
            phrase = matchingPhrases[tracker.index]
            found = true
        end
    end

    if found and type(phrase) == "table" then
        SKIN:Bang('!SetOption', 'PhraseText', 'Text', phrase.title)
        SKIN:Bang('!SetOption', 'SublineText', 'Text', phrase.subline)
        SKIN:Bang('!SetOption', 'PhraseText', 'InlineSetting', 'Color | ' .. phrase.color)
        if phrase.highlight and #phrase.highlight > 0 then
            SKIN:Bang('!SetOption', 'PhraseText', 'InlinePattern', '(' .. phrase.highlight[1] .. ')')
        else
            SKIN:Bang('!SetOption', 'PhraseText', 'InlinePattern', '')
        end
        -- Force immediate update of meters
        SKIN:Bang('!UpdateMeter', 'PhraseText')
        SKIN:Bang('!UpdateMeter', 'SublineText')
        SKIN:Bang('!Redraw')
        return phrase.title
    else
        SKIN:Bang('!Log', 'No se encontró una frase que matchee', 'Error')
        SKIN:Bang('!SetOption', 'PhraseText', 'Text', "Cargando...")
        SKIN:Bang('!SetOption', 'SublineText', 'Text', "Andá a cebarte un verde mientras.")
        SKIN:Bang('!SetOption', 'PhraseText', 'InlineSetting', '')
        SKIN:Bang('!SetOption', 'PhraseText', 'InlinePattern', '')
        SKIN:Bang('!UpdateMeter', 'PhraseText')
        SKIN:Bang('!UpdateMeter', 'SublineText')
        SKIN:Bang('!Redraw')
        return "Cargando..."
    end
end

