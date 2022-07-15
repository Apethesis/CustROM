local function printUsage()
    local programName = arg[0] or fs.getName(shell.getRunningProgram())
    print("Usages:")
    print(programName .. " put <filename>")
    print(programName .. " get <code> <filename>")
    print(programName .. " run <code> <arguments>")
end

local tArgs = {...}
if #tArgs < 2 then
    printUsage()
    return
end

if not http then
    printError("DevBin requires the http API")
    printError("Set http.enabled to true in CC: Tweaked's config")
    return
end

--- Attempts to guess the DevBin ID from the given code or URL
local function extractId(paste)
    local patterns = {
        "^([%a%d]+)$",
        "^https?://devbin.dev/([%a%d]+)$",
        "^devbin.dev/([%a%d]+)$",
        "^https?://devbin.dev/raw/([%a%d]+)$",
        "^devbin.dev/raw/([%a%d]+)$"
    }

    for i = 1, #patterns do
        local code = paste:match(patterns[i])
        if code then
            return code
        end
    end

    return nil
end

local function get(url)
    local paste = extractId(url)
    if not paste then
        io.stderr:write("Invalid DevBin code.\n")
        io.write("The code is the ID at the end of the devbin.dev URL.\n")
        return
    end

    write("Connecting to devbin.dev... ")
    -- Add a cache buster so that spam protection is re-checked
    local cacheBuster = ("%x"):format(math.random(0, 2 ^ 30))
    local response, err = http.get("https://devbin.dev/raw/" .. textutils.urlEncode(paste) .. "?cb=" .. cacheBuster)

    if response then
        -- If spam protection is activated, we get redirected to /paste with Content-Type: text/html
        -- Should not happen with DevBin
        local headers = response.getResponseHeaders()
        if not headers["Content-Type"] or not headers["Content-Type"]:find("^text/plain") then
            io.stderr:write("Failed.\n")
            print(
                "DevBin blocked the download due to spam protection. Please complete the captcha in a web browser: https://devbin.dev/" ..
                    textutils.urlEncode(paste)
            )
            return
        end

        print("Success.")

        local sResponse = response.readAll()
        response.close()
        return sResponse
    else
        io.stderr:write("Failed.\n")
        print(err)
    end
end

local key = settings.get("devbin.token", "computercraft")
local uploadAsGuest = settings.get("devbin.upload_as_guest", true)

if not settings.get("devbin.token") then
    settings.set("devbin.token", key)
end
if settings.get("devbin.upload_as_guest") == nil then
    settings.set("devbin.upload_as_guest", true)
end

local sCommand = tArgs[1]
if sCommand == "put" then
    -- Upload a file to devbin.dev
    -- Determine file to upload
    local sFile = tArgs[2]
    local sPath = shell.resolve(sFile)
    if not fs.exists(sPath) or fs.isDir(sPath) then
        print("No such file")
        return
    end

    -- Read in the file
    local sName = fs.getName(sPath)
    local file = fs.open(sPath, "r")
    local sText = file.readAll()
    file.close()

    -- POST the contents to devbin
    write("Connecting to devbin.dev... ")
    local response, err =
        http.post(
        "https://devbin.dev/api/v2/paste",
        textutils.serialiseJSON({
            title = sName,
            syntax = "lua",
            content = sText,
            asGuest = uploadAsGuest,
        }),
        {
            ["Authorization"] = key,
            ["Content-Type"] = "application/json",
        }
    )

    if response then
        print("Success.")

        local sResponse = response.readAll()
        response.close()
        sResponse = textutils.unserialiseJSON(sResponse);

        local sCode = sResponse.code;
        print("Uploaded as https://devbin.dev/" .. sCode)
        print('Run "devbin get ' .. sCode .. '" to download anywhere')
    else
        print("Failed.", err)
    end
elseif sCommand == "get" then
    -- Download a file from devbin.dev
    if #tArgs < 3 then
        printUsage()
        return
    end

    -- Determine file to download
    local sCode = tArgs[2]
    local sFile = tArgs[3]
    local sPath = shell.resolve(sFile)
    if fs.exists(sPath) then
        print("File already exists")
        return
    end

    -- GET the contents from devbin
    local res = get(sCode)
    if res then
        local file = fs.open(sPath, "w")
        file.write(res)
        file.close()

        print("Downloaded as " .. sFile)
    end
elseif sCommand == "run" then
    local sCode = tArgs[2]

    local res = get(sCode)
    if res then
        local func, err = load(res, sCode, "t", _ENV)
        if not func then
            printError(err)
            return
        end
        local success, msg = pcall(func, select(3, ...))
        if not success then
            printError(msg)
        end
    end
else
    printUsage()
    return
end
