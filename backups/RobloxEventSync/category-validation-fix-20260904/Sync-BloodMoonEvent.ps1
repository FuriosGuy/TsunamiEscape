[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),
    [switch]$Apply,
    [int]$MaxPages = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ApiRoot = "https://apis.roblox.com/virtual-events/v3"
$ApiKeyEnvironmentVariable = "ROBLOX_EVENT_API_KEY"
$LocalDotEnvPath = Join-Path $PSScriptRoot ".env"

function Import-LocalDotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#")) {
            continue
        }

        if ($trimmedLine -notmatch '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            Write-Warning "Ignoring malformed .env line."
            continue
        }

        $name = $Matches[1]
        if ($name -ne $ApiKeyEnvironmentVariable) {
            continue
        }

        $value = $Matches[2].Trim()
        if ($value.Length -ge 2) {
            $firstCharacter = $value.Substring(0, 1)
            $lastCharacter = $value.Substring($value.Length - 1, 1)
            if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^<.*>$') {
            continue
        }

        $existingValue = [Environment]::GetEnvironmentVariable($name, "Process")
        if ([string]::IsNullOrWhiteSpace($existingValue)) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Resolve-LocalPath {
    param([string]$PathValue)

    if ([IO.Path]::IsPathRooted($PathValue)) {
        return [IO.Path]::GetFullPath($PathValue)
    }

    $currentDirectoryPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $PathValue))
    if (Test-Path -LiteralPath $currentDirectoryPath) {
        return $currentDirectoryPath
    }

    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $PathValue))
}

function Convert-ToUtcTimestamp {
    param(
        [object]$Value,
        [string]$FieldName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "$FieldName must contain an RFC 3339 timestamp."
    }

    try {
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        $parsed = [DateTimeOffset]::Parse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            $styles
        )
        return $parsed.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    } catch {
        throw "$FieldName is not a valid RFC 3339 timestamp: $Value"
    }
}

function Convert-ToInt64 {
    param(
        [object]$Value,
        [string]$FieldName
    )

    $parsed = 0L
    $success = [long]::TryParse(
        [string]$Value,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )
    if (-not $success -or $parsed -le 0) {
        throw "$FieldName must be a positive integer."
    }

    return $parsed
}

function Get-RequiredString {
    param(
        [object]$Object,
        [string]$Name
    )

    $value = Get-PropertyValue $Object $Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw "Config field '$Name' is required."
    }

    return [string]$value
}

function Invoke-RobloxEventRequest {
    param(
        [ValidateSet("GET", "POST", "PATCH")]
        [string]$Method,
        [string]$Uri,
        [object]$Body
    )

    $headers = @{
        "x-api-key" = $script:ApiKey
        Accept = "application/json"
    }
    $bodyJson = if ($null -ne $Body) {
        $Body | ConvertTo-Json -Depth 12 -Compress
    } else {
        $null
    }

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            if ($null -eq $bodyJson) {
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ErrorAction Stop
            }

            return Invoke-RestMethod `
                -Method $Method `
                -Uri $Uri `
                -Headers $headers `
                -ContentType "application/json" `
                -Body $bodyJson `
                -ErrorAction Stop
        } catch {
            $response = $_.Exception.Response
            $statusCode = 0
            if ($null -ne $response) {
                $statusCode = [int]$response.StatusCode
            }

            $isRetryable = $statusCode -eq 429 -or $statusCode -ge 500
            if ($isRetryable -and $attempt -lt 4) {
                $delaySeconds = [int][Math]::Pow(2, $attempt - 1)
                $retryAfter = if ($null -ne $response) {
                    $response.Headers["Retry-After"]
                } else {
                    $null
                }
                if ($null -ne $retryAfter) {
                    $parsedRetryAfter = 0
                    if ([int]::TryParse([string]$retryAfter, [ref]$parsedRetryAfter)) {
                        $delaySeconds = [Math]::Max($delaySeconds, $parsedRetryAfter)
                    }
                }

                Write-Warning "Roblox API returned HTTP $statusCode. Retrying in ${delaySeconds}s (attempt $attempt/4)."
                Start-Sleep -Seconds $delaySeconds
                continue
            }

            $errorDetail = $_.Exception.Message
            if ($null -ne $response) {
                try {
                    $reader = [IO.StreamReader]::new($response.GetResponseStream())
                    $serverBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    if (-not [string]::IsNullOrWhiteSpace($serverBody)) {
                        $errorDetail = "$errorDetail | response=$serverBody"
                    }
                } catch {
                    # Preserve the original HTTP error when the response body is unavailable.
                }
            }

            throw "Roblox API request failed: $Method $Uri | HTTP $statusCode | $errorDetail"
        }
    }

    throw "Roblox API request failed after all retry attempts: $Method $Uri"
}

function Get-AllEvents {
    param(
        [long]$UniverseId,
        [int]$PageLimit
    )

    $events = [Collections.Generic.List[object]]::new()
    $pageToken = $null

    for ($pageNumber = 1; $pageNumber -le $PageLimit; $pageNumber++) {
        $uri = "$script:ApiRoot/universes/$UniverseId/game-events?pageSize=100&fields=*"
        if (-not [string]::IsNullOrWhiteSpace([string]$pageToken)) {
            $encodedToken = [Uri]::EscapeDataString([string]$pageToken)
            $uri += "&pageToken=$encodedToken"
        }

        $page = Invoke-RobloxEventRequest -Method GET -Uri $uri
        $pageEvents = Get-PropertyValue $page "gameEvents"
        foreach ($event in @($pageEvents)) {
            if ($null -ne $event) {
                $events.Add($event)
            }
        }

        $pageToken = Get-PropertyValue $page "nextPageToken"
        if ([string]::IsNullOrWhiteSpace([string]$pageToken)) {
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$pageToken)) {
        Write-Warning "Event list reached MaxPages=$PageLimit before pagination finished. No automatic create will be attempted from an incomplete list."
        throw "Event list is incomplete. Increase -MaxPages before applying changes."
    }

    return @($events)
}

function New-EventPayload {
    param(
        [object]$Config,
        [long]$PlaceId,
        [long]$GroupId = 0
    )

    $startTime = Convert-ToUtcTimestamp (Get-PropertyValue $Config "startTimeUtc") "startTimeUtc"
    $endTime = Convert-ToUtcTimestamp (Get-PropertyValue $Config "endTimeUtc") "endTimeUtc"
    $start = [DateTimeOffset]::Parse($startTime, [Globalization.CultureInfo]::InvariantCulture)
    $end = [DateTimeOffset]::Parse($endTime, [Globalization.CultureInfo]::InvariantCulture)
    if ($end -le $start) {
        throw "endTimeUtc must be after startTimeUtc."
    }

    $visibility = (Get-RequiredString $Config "visibility").ToLowerInvariant()
    if ($visibility -notin @("public", "private")) {
        throw "visibility must be 'public' or 'private'."
    }

    $payload = [ordered]@{
        title = Get-RequiredString $Config "title"
        subtitle = Get-RequiredString $Config "subtitle"
        description = Get-PropertyValue $Config "description"
        startTime = $startTime
        endTime = $endTime
        visibility = $visibility
        placeId = $PlaceId
    }

    if ($GroupId -gt 0) {
        $payload.groupId = $GroupId
    }

    $tagline = Get-PropertyValue $Config "tagline"
    if ($null -ne $tagline -and -not [string]::IsNullOrWhiteSpace([string]$tagline)) {
        $payload.tagline = [string]$tagline
    }

    $thumbnailId = Get-PropertyValue $Config "thumbnailId"
    if ($null -ne $thumbnailId -and -not [string]::IsNullOrWhiteSpace([string]$thumbnailId)) {
        $payload.thumbnails = @(
            [ordered]@{
                mediaId = Convert-ToInt64 $thumbnailId "thumbnailId"
                rank = 1
            }
        )
    }

    $categoriesConfig = Get-PropertyValue $Config "categories"
    if ($null -ne $categoriesConfig) {
        $allowedCategories = @(
            "contentUpdate", "locationUpdate", "systemUpdate", "activity", "newContent",
            "itemDrop", "newSeason", "newLocation", "newMap", "moreLevels", "newFeature",
            "earlyAccess", "expansion", "challenge", "quest", "festival"
        )
        $categories = [Collections.Generic.List[object]]::new()
        foreach ($categoryConfig in @($categoriesConfig)) {
            $category = Get-RequiredString $categoryConfig "category"
            if ($category -notin $allowedCategories) {
                throw "Unsupported event category '$category'."
            }

            $rank = Convert-ToInt64 (Get-PropertyValue $categoryConfig "rank") "category rank"
            $categories.Add([ordered]@{
                category = $category
                rank = [int]$rank
            })
        }
        if ($categories.Count -gt 0) {
            $payload.categories = @($categories)
        }
    }

    $notificationAudience = Get-PropertyValue $Config "notificationAudience"
    $recurrence = Get-PropertyValue $Config "recurrence"
    $recurrenceEndTimeUtc = Get-PropertyValue $Config "recurrenceEndTimeUtc"
    if ($null -ne $notificationAudience -or $null -ne $recurrence -or $null -ne $recurrenceEndTimeUtc) {
        $eventConfig = [ordered]@{}
        if ($null -ne $notificationAudience) {
            $audience = ([string]$notificationAudience).ToLowerInvariant()
            if ($audience -notin @("all", "rsvp", "subscribed", "group", "none")) {
                throw "notificationAudience must be all, rsvp, subscribed, group, or none."
            }
            $eventConfig.notificationAudience = $audience
        }
        if ($null -ne $recurrence -and -not [string]::IsNullOrWhiteSpace([string]$recurrence)) {
            $eventConfig.recurrence = [string]$recurrence
        }
        if ($null -ne $recurrenceEndTimeUtc -and -not [string]::IsNullOrWhiteSpace([string]$recurrenceEndTimeUtc)) {
            $eventConfig.recurrenceEndTime = Convert-ToUtcTimestamp $recurrenceEndTimeUtc "recurrenceEndTimeUtc"
        }
        if ($eventConfig.Count -gt 0) {
            $payload.config = $eventConfig
        }
    }

    return [pscustomobject]$payload
}

function Get-ManagedEvent {
    param(
        [object]$Config,
        [object]$State,
        [long]$UniverseId,
        [long]$PlaceId,
        [int]$PageLimit
    )

    $managedEventId = Get-PropertyValue $Config "managedEventId"
    if ([string]::IsNullOrWhiteSpace([string]$managedEventId)) {
        $managedEventId = Get-PropertyValue $State "eventId"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$managedEventId)) {
        $eventId = Convert-ToInt64 $managedEventId "managedEventId"
        $uri = "$script:ApiRoot/game-events/$eventId`?fields=*"
        try {
            return Invoke-RobloxEventRequest -Method GET -Uri $uri
        } catch {
            if ($_.Exception.Message -notmatch "HTTP 404") {
                throw
            }

            Write-Warning "Stored event ID $eventId was not found. Listing current events before considering creation."
        }
    }

    $events = Get-AllEvents -UniverseId $UniverseId -PageLimit $PageLimit
    $title = Get-RequiredString $Config "title"
    $matchingTitleAndPlace = @($events | Where-Object {
        ([string](Get-PropertyValue $_ "title") -eq $title) -and
        ([string](Get-PropertyValue $_ "placeId") -eq [string]$PlaceId)
    })
    $startTime = Convert-ToUtcTimestamp (Get-PropertyValue $Config "startTimeUtc") "startTimeUtc"
    $exactSchedule = @($matchingTitleAndPlace | Where-Object {
        (Convert-ToUtcTimestamp (Get-PropertyValue $_ "startTime") "event startTime") -eq $startTime
    })

    if ($exactSchedule.Count -eq 1) {
        return $exactSchedule[0]
    }
    if ($exactSchedule.Count -gt 1) {
        throw "Multiple events match the configured title, place, and start time. Set managedEventId explicitly."
    }
    if ($matchingTitleAndPlace.Count -gt 0) {
        throw "A same-title event already exists at the DEV place with a different schedule. Set managedEventId explicitly instead of creating a duplicate."
    }

    return $null
}

function Test-EventCoreFields {
    param(
        [object]$Event,
        [object]$Payload
    )

    $coreFieldsMatch =
        ([string](Get-PropertyValue $Event "title") -eq [string](Get-PropertyValue $Payload "title")) -and
        ([string](Get-PropertyValue $Event "subtitle") -eq [string](Get-PropertyValue $Payload "subtitle")) -and
        ([string](Get-PropertyValue $Event "placeId") -eq [string](Get-PropertyValue $Payload "placeId")) -and
        ((Convert-ToUtcTimestamp (Get-PropertyValue $Event "startTime") "returned startTime") -eq [string](Get-PropertyValue $Payload "startTime")) -and
        ((Convert-ToUtcTimestamp (Get-PropertyValue $Event "endTime") "returned endTime") -eq [string](Get-PropertyValue $Payload "endTime")) -and
        (([string](Get-PropertyValue $Event "visibility")).ToLowerInvariant() -eq ([string](Get-PropertyValue $Payload "visibility")).ToLowerInvariant())

    return $coreFieldsMatch
}

function Write-State {
    param(
        [string]$Path,
        [object]$Event,
        [object]$Payload,
        [long]$UniverseId
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $state = [ordered]@{
        eventId = [string](Get-PropertyValue $Event "id")
        eventKey = "bloodmoon-$((Get-PropertyValue $Payload "startTime"))"
        universeId = [string]$UniverseId
        placeId = [string](Get-PropertyValue $Payload "placeId")
        startTime = [string](Get-PropertyValue $Payload "startTime")
        endTime = [string](Get-PropertyValue $Payload "endTime")
        lastSyncStatus = "success"
        lastSyncUtc = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

try {
    Import-LocalDotEnv -Path $LocalDotEnvPath

    $configFile = Resolve-LocalPath $ConfigPath
    if (-not (Test-Path -LiteralPath $configFile)) {
        throw "Config not found: $configFile. Copy config.example.json to config.json first."
    }

    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    $universeId = Convert-ToInt64 (Get-PropertyValue $config "universeId") "universeId"
    $placeId = Convert-ToInt64 (Get-PropertyValue $config "placeId") "placeId"
    $groupId = 0
    $groupIdValue = Get-PropertyValue $config "groupId"
    if ($null -ne $groupIdValue -and -not [string]::IsNullOrWhiteSpace([string]$groupIdValue)) {
        $groupId = Convert-ToInt64 $groupIdValue "groupId"
    }
    $stateFileValue = Get-PropertyValue $config "stateFile"
    $stateFile = if ($null -ne $stateFileValue -and -not [string]::IsNullOrWhiteSpace([string]$stateFileValue)) {
        Resolve-LocalPath ([string]$stateFileValue)
    } else {
        Resolve-LocalPath "event-state.json"
    }

    $state = if (Test-Path -LiteralPath $stateFile) {
        Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    } else {
        $null
    }
    $payload = New-EventPayload -Config $config -PlaceId $placeId -GroupId $groupId
    $payloadJson = $payload | ConvertTo-Json -Depth 12

    Write-Host "Roblox Event Sync"
    Write-Host "Target: universe=$universeId | group=$groupId | place=$placeId | title=$($payload.title)"
    Write-Host "Window: $($payload.startTime) to $($payload.endTime)"
    Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
    Write-Host "Payload:"
    Write-Host $payloadJson

    if (-not $Apply) {
        Write-Host "Dry-run complete. No Roblox API request was made. Use -Apply only after reviewing the payload."
        exit 0
    }

    $script:ApiKey = [Environment]::GetEnvironmentVariable($ApiKeyEnvironmentVariable)
    if ([string]::IsNullOrWhiteSpace($script:ApiKey)) {
        throw "Missing environment variable $ApiKeyEnvironmentVariable. The API key is never read from config or source code."
    }

    $existingEvent = Get-ManagedEvent `
        -Config $config `
        -State $state `
        -UniverseId $universeId `
        -PlaceId $placeId `
        -PageLimit $MaxPages

    if ($null -ne $existingEvent) {
        $existingId = Convert-ToInt64 (Get-PropertyValue $existingEvent "id") "existing event id"
        Write-Host "Updating existing event: $existingId"
        $updatedEvent = Invoke-RobloxEventRequest `
            -Method PATCH `
            -Uri "$ApiRoot/game-events/$existingId" `
            -Body $payload
        $managedEvent = $updatedEvent
    } else {
        Write-Host "Creating new Blood Moon event."
        $createdEvent = Invoke-RobloxEventRequest `
            -Method POST `
            -Uri "$ApiRoot/universes/$universeId/game-events" `
            -Body $payload
        $managedEvent = $createdEvent
    }

    $managedEventId = Convert-ToInt64 (Get-PropertyValue $managedEvent "id") "returned event id"
    $verifiedEvent = Invoke-RobloxEventRequest -Method GET -Uri "$ApiRoot/game-events/$managedEventId`?fields=*"
    if (-not (Test-EventCoreFields -Event $verifiedEvent -Payload $payload)) {
        throw "Verification failed for event $managedEventId. State was not written."
    }

    $requestedThumbnail = Get-PropertyValue $payload "thumbnails"
    if ($null -ne $requestedThumbnail) {
        $returnedThumbnail = Get-PropertyValue $verifiedEvent "thumbnails"
        if ($null -eq $returnedThumbnail -or @($returnedThumbnail).Count -eq 0) {
            Write-Warning "Roblox accepted the event but returned no thumbnail. Check moderation/asset processing in Creator Dashboard."
        }
    }

    Write-State -Path $stateFile -Event $verifiedEvent -Payload $payload -UniverseId $universeId
    Write-Host "Sync succeeded: eventId=$managedEventId"
    Write-Host "State written: $stateFile"
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
