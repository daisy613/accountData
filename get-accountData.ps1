### keys
$accounts = @(
    [PSCustomObject]@{ "number" = "1"; "exchange" = "binance"; "name" = "myAccount1"; "key" = "xxxxxxxxxx"; "secret" = "xxxxxxxxxx" },
    [PSCustomObject]@{ "number" = "2"; "exchange" = "binance"; "name" = "myOtherAccount"; "key" = "xxxxxxxxxx"; "secret" = "xxxxxxxxxx" },
    [PSCustomObject]@{ "number" = "3"; "exchange" = "binance"; "name" = "myCatsAccount"; "key" = "xxxxxxxxxx"; "secret" = "xxxxxxxxxx" }
)

function getLocalTime {
    param( [parameter(Mandatory = $true)] [String] $UTCTime )
    $strCurrentTimeZone = (Get-WmiObject win32_timezone).StandardName
    $TZ = [System.TimeZoneInfo]::FindSystemTimeZoneById($strCurrentTimeZone)
    $LocalTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($UTCTime, $TZ)
    return $LocalTime
}

### get symbols
function getSymbols () {
    $exchangeInfo = "https://fapi.binance.com/fapi/v1/exchangeInfo"
    $symbols = ((Invoke-RestMethod -Uri $exchangeInfo).symbols).symbol | Sort-Object
    return $symbols
}

### get account info
function getAccount () {
    Param(
        [Parameter(Mandatory = $false, Position = 0)]$accountNum
    )
    $key = ($accounts | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accounts | Where-Object { $_.number -eq $accountNum }).secret
    $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $QueryString = "&recvWindow=5000&timestamp=$TimeStamp"
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
    $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
    $uri = "https://fapi.binance.com/fapi/v1/account?$QueryString&signature=$signature"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-MBX-APIKEY", $key)
    $result = @()
    $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get | select totalInitialMargin,totalMaintMargin,totalWalletBalance,totalUnrealizedProfit,totalMarginBalance,availableBalance
    $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($TimeStamp).DateTime)
    $result | ForEach {
        Add-Member -InputObject $result -NotePropertyName "time" -NotePropertyValue $TimeStamp -Force -PassThru | out-null
        Add-Member -InputObject $result -NotePropertyName "datetime" -NotePropertyValue $datetime.ToString("yyyy-MM-dd HH:mm:ss") -Force -PassThru | out-null
    }
    return $result
}

function getOrders () {
    # https://binance-docs.github.io/apidocs/futures/en/#account-trade-list-user_data
    Param([Parameter(Mandatory = $True, Position = 0)]$symbol,
        [Parameter(Mandatory = $false, Position = 1)]$accountNum,
        [Parameter(Mandatory = $false, Position = 2)]$startTime,
        [Parameter(Mandatory = $false, Position = 3)]$fromId
    )
    $key = ($accounts | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accounts | Where-Object { $_.number -eq $accountNum }).secret
    $limit = "1000"    # max 1000
    $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $QueryString = "&recvWindow=5000&limit=$limit&timestamp=$TimeStamp&symbol=$symbol&fromId=$fromId&startTime=$startTime"
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
    $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
    $uri = "https://fapi.binance.com/fapi/v1/userTrades?$QueryString&signature=$signature"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-MBX-APIKEY", $key)
    $results = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    foreach ($result in $results) {
        $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($result.time).DateTime)
        Add-Member -InputObject $result -NotePropertyName "datetime" -NotePropertyValue $datetime.ToString("yyyy-MM-dd HH:mm:ss") -Force -PassThru
    }
    return $results
}
# $result = getOrders "AAVEUSDT" 1 "" | select symbol,time,id | sort time

function getIncome () {
    # https://binance-docs.github.io/apidocs/futures/en/#get-income-history-user_data
    Param([Parameter(Mandatory = $false, Position = 0)]$accountNum,
        [Parameter(Mandatory = $false, Position = 1)]$startTime
    )
    $key = ($accounts | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accounts | Where-Object { $_.number -eq $accountNum }).secret
    $limit = "1000"    # max 1000
    do {
        $result = @()
        $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $QueryString = "&recvWindow=5000&limit=$limit&timestamp=$TimeStamp&startTime=$startTime"
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
        $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
        $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
        $uri = "https://fapi.binance.com/fapi/v1/income?$QueryString&signature=$signature"
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("X-MBX-APIKEY", $key)
        $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $results += $result
        if ($result.length -lt 1000)    { break }
        else {
            $startTime = [int64]($result.time | sort)[-1] + 1
            $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $QueryString = "&recvWindow=5000&limit=$limit&timestamp=$TimeStamp&startTime=$startTime"
            $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
            $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
            $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
            $uri = "https://fapi.binance.com/fapi/v1/income?$QueryString&signature=$signature"
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("X-MBX-APIKEY", $key)
            $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            $results += $result
            if ($result.length -lt 1000) { break }
            $startTime = [int64]($result.time | sort)[-1] + 1
        }
    } while ($result.length -gt 1)
    $results = $results | ? { $_.incomeType -ne "COMMISSION" -and $_.incomeType -ne "REALIZED_PNL" }
    foreach ($result in $results) {
        $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($result.time).DateTime)
        Add-Member -InputObject $result -NotePropertyName "datetime" -NotePropertyValue $datetime.ToString("yyyy-MM-dd HH:mm:ss") -Force -PassThru | out-null
    }
    return $results
}

function addAccount () {
    $dataRoot = "E:\BOTS\Zacct\data"
    foreach ($account in $accounts) {
        $file = "$($dataRoot)\data_account$($account.number).csv"
        $results = getAccount $account.number
        $results | ConvertTo-Csv -NoTypeInformation | select -Skip 1 | ac $file
        write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]`taddAccount`taccount: $($account.number)`t$($results.length)" -ForegroundColor Green
    }
}

### add orders
function addOrders () {
    $dataRoot = "E:\acct\data"
    foreach ($account in $accounts) {
        $file = "$($dataRoot)\data_orders$($account.number).csv"
        $lastTime = $null
        $symbols = getSymbols
        $orders = @()
        foreach ($symbol in $symbols) {
            $results = @()
            $result = @()
            $lastTime = $null
            $lastTime = [int64]((gc $file -tail 1).split(",")[11] -replace '"','') + 1
            do {
                $result = @()
                $result = getOrders $symbol $account.number $lastTime
                $results += $result
                if ($result.length -lt 2000)    { break }
                else {
                    $lastTime = [int64]($result.time | sort)[-1] + 1
                    $result = getOrders $symbol $account.number $lastTime
                    $results += $result
                    if ($result.length -lt 2000) { break }
                    $lastTime = [int64]($result.time | sort)[-1] + 1
                }
            } while ($result.length -gt 1)
            write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]`tOrders`taccount: $($account.number)`t$($symbol):`t$($results.length)" -ForegroundColor Blue
            $orders += $results
        }
        $orders | sort -uniq -property id | sort time | ConvertTo-Csv -NoTypeInformation | select -Skip 1 | ac $file
    }
}

function addIncome () {
    $dataRoot = "E:\acct\data"
    foreach ($account in $accounts) {
        $file = "$($dataRoot)\data_income$($account.number).csv"
        $lastTime = [int64]((gc $file -tail 1).split(",")[4] -replace '"','') + 1
        $results = getIncome $account.number $lastTime
        write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]`taddIncome`taccount: $($account.number)`t$($results.length)" -ForegroundColor Magenta
        $results | sort time | ConvertTo-Csv -NoTypeInformation | select -Skip 1 | ac $file
    }
}

addAccount
addIncome
addOrders
