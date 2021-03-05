### Changelog:
### * added COIN-M logic
### * removed Herobrine

### For Binance USD-M Futures: do not specify a symbol in the settings.
### For Binance COIN-M Futures: for symbol in the settings specify one of the assets supported by COIN-M (ADA,BCH,BNB,BTC,DOGE,DOT,EGLD,EOS,ETC,ETH,FIL,LINK,LTC,TRX,XRP). Use one account entry per each COINS-M asset.
### For Bybit: for symbol in the settings specify a one of the assets supported by Bybit (BTC,ETH,EOS,XRP)

### run powershell as admin
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $path = Split-Path $MyInvocation.MyCommand.Path
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments -WorkingDirectory $path
    Break
}

$version = "v1.1.0"
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

Install-Module PSSQLite
Import-Module PSSQLite

$path = Split-Path $MyInvocation.MyCommand.Path
$dataSource = "$($path)\db-files\accountData.db"
$logfile = "$($path)\accountData.log"
$refresh = 10 # minutes
$accountSettings = (gc "$($path)\accountData.json"  | ConvertFrom-Json) | ? { $_.enabled -eq "true" }

if (!($accountSettings)) { write-host "Cannot find $($path)\accountData.json file!" -foregroundcolor "DarkRed" -backgroundcolor "yellow"; sleep 30 ; exit }

write-host "`n`n`n`n`n`n`n`n`n`n"

### create transactions table if doesn't exist
$Query = "CREATE TABLE if not exists Transactions ( accountNum INTEGER, exchange TEXT, name TEXT, symbol TEXT, incomeType TEXT, income NUMERIC, asset TEXT, info TEXT, tranId TEXT, tradeId TEXT, totalWalletBalance NUMERIC, totalUnrealizedProfit NUMERIC, todayRealizedPnl NUMERIC, totalRealizedPnl NUMERIC, source TEXT, time INTEGER, datetime DATETIME )"
Invoke-SqliteQuery -DataSource $DataSource -Query $Query
### optimize the existing db
Invoke-SqliteQuery -DataSource $DataSource -Query "PRAGMA optimize"

function checkLatest () {
    $repo = "daisy613/get-accountData"
    $releases = "https://api.github.com/repos/$repo/releases"
    $latestTag = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name | out-null
    $youngerVer = ($version, $latestTag | Sort-Object)[-1]
    if ($latestTag -and $version -ne $youngerVer) {
        write-log -string "Your version [$($version)] is outdated. Newer version [$($latestTag)] is available here: https://github.com/$($repo)/releases/tag/$($latestTag)" -color "Red"
    }
}

Function write-log {
    Param ([string]$string,$color="Yellow")
    $date = Get-Date -Format "$($version) yyyy-MM-dd HH:mm:ss"
    Write-Host "[$date] $string" -ForegroundColor $color
    Add-Content $Logfile -Value "[$date] $string"
}

# function getLocalTime {
#     param( [parameter(Mandatory = $true)] [String] $UTCTime )
#     $strCurrentTimeZone = (Get-WmiObject win32_timezone).StandardName
#     $TZ = [System.TimeZoneInfo]::FindSystemTimeZoneById($strCurrentTimeZone)
#     $LocalTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($UTCTime, $TZ)
#     return $LocalTime
# }

# function Convert-UnixTime {
#     Param( [Parameter(Mandatory=$true)][int32]$udate )
#     $Timezone = (Get-TimeZone)
#     if ($Timezone.SupportsDaylightSavingTime -eq $True) {
#         $TimeAdjust =  ($Timezone.BaseUtcOffset.TotalSeconds + 3600)
#     } else {
#         $TimeAdjust = ($Timezone.BaseUtcOffset.TotalSeconds)
#     }
#     # Adjust time from UTC to local based on offset that was determined before.
#     $udate = ($udate + $TimeAdjust)
#     # Retrieve start of UNIX Format
#     $orig = (Get-Date -Year 1970 -Month 1 -Day 1 -hour 0 -Minute 0 -Second 0 -Millisecond 0)
#     # Return final time
#     return $orig.AddSeconds($udate)
# }

Function getLocalTime {
    <#
    .Synopsis
    Convert a ctime value to a datetime value
    .Description
    Convert a ctime value to a more meaningful datetime value. The default behavior is to convert to local time, including any daylight saving time offset. Or you can view the time in GMT.
    .Parameter GMT
    Don't convert to local time.
    .Example
    PS C:\> getLocalTime 1426582884.043993
    Tuesday, March 17, 2015 5:01:24 AM
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,Mandatory,
        HelpMessage = "Enter a ctime value",
        ValueFromPipeline)]
        [ValidateNotNullorEmpty()]
        [double]$Ctime,
        [switch]$GMT
    )
    Begin {
        $Ctime = $Ctime / 1000
        Write-Verbose "Starting $($MyInvocation.Mycommand)"
        #define universal starting time
        [datetime]$utc = "1/1/1970"
        #test for Daylight Saving Time
        Write-Verbose "Checking DaylightSavingTime"
        $dst = Get-Ciminstance -ClassName Win32_Computersystem -filter "DaylightInEffect = 'True'"
    } #begin
    Process {
        Write-Verbose "Processing $ctime"
        #add the ctime value which should be the number of
        #seconds since 1/1/1970.
        $gmtTime = $utc.AddSeconds($ctime)
        if ($gmt) {
            #display default time which should be GMT if
            #user used -GMT parameter
            Write-verbose "GMT"
            $gmtTime
        }
        else {
            #otherwise convert to the local time zone
            Write-Verbose "Converting to $gmtTime to local time zone"
            #get time zone information from WMI
            $tz = Get-CimInstance -ClassName Win32_TimeZone
            #the bias is the number of minutes offset from GMT
            Write-Verbose "Timezone offset = $($tz.Bias)"
            #Add the necessary number of minutes to convert
            #to the local time.
            $local = $gmtTime.AddMinutes($tz.bias)
            if ($dst) {
                Write-Verbose "DST in effect with bias = $($tz.daylightbias)"
                $local.AddMinutes(-($tz.DaylightBias))
            }
            else {
                #write the local time
                $local
            }
        }
    } #process
    End {
        Write-Verbose "Ending $($MyInvocation.Mycommand)"
    } #end
} #close Convert-Ctime function

function date2unix () {
    param ($dateTime)
    $unixTime = ([DateTimeOffset]$dateTime).ToUnixTimeMilliseconds()
    return $unixTime
}

function unix2date () {
    param ($utcTime)
    $datetime = [datetimeoffset]::FromUnixTimeMilliseconds($utcTime).DateTime
    return $datetime
}

function getPrice () {
    Param($symbol,$startTime)
    $symbol = $symbol + "USDT"
    $limit = 1
    $klines = "https://fapi.binance.com/fapi/v1/klines?symbol=$($symbol)&interval=1m&limit=$($limit)&startTime=$($startTime)"
    while ($true) {
      $klinesInformation = Invoke-RestMethod -Uri $klines
      if (($klinesInformation[0])[4]) { break }
      sleep 1
    }
    $price = [decimal] ($klinesInformation[0])[4]
    return $price
}

function betterSleep () {
    Param ($seconds,$message)
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $minutes = [math]::Round(($seconds / 60),2)
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "$($message)" -Status "Sleeping $($minutes) minutes..." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "$($message)" -Status "Sleeping $($minutes) minutes..." -SecondsRemaining 0 -Completed
}

### get account info
function getAccount () {
    Param(
        [Parameter(Mandatory = $false, Position = 0)]$accountNum
    )
    $accountSettings = (gc "$($path)\accountData.json"  | ConvertFrom-Json) | ? { $_.enabled -eq "true" }
    $exchange = ($accountSettings | Where-Object { $_.number -eq $accountNum }).exchange
    $accountName = ($accountSettings | Where-Object { $_.number -eq $accountNum }).name
    $key = ($accountSettings | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accountSettings | Where-Object { $_.number -eq $accountNum }).secret
    $symbol = ($accountSettings | Where-Object { $_.number -eq $accountNum }).symbol
    $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($exchange -eq "binance") {
        if (!($symbol)) {  #if no symbol specified, it's USD-M Futures
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
            $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get | Select-Object totalWalletBalance, totalUnrealizedProfit
            $datetime = getLocalTime $TimeStamp
            $newItem = [PSCustomObject]@{
                "accountNum"            = $accountNum
                "exchange"              = $exchange
                "name"                  = $accountName
                "symbol"                = $null
                "incomeType"            = $null
                "income"                = $null
                "asset"                 = $null
                "info"                  = $null
                "tranId"                = $null
                "tradeId"               = $null
                "totalWalletBalance"    = $result.totalWalletBalance
                "totalUnrealizedProfit" = $result.totalUnrealizedProfit
                "todayRealizedPnl"      = $null
                "totalRealizedPnl"      = $null
                "source"                = "account"
                "time"                  = [int64] $TimeStamp
                "datetime"              = $datetime
            }
            return $newItem
        }
        else { #if symbol is specified, it's COIN-M Futures
            $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $QueryString = "&recvWindow=5000&timestamp=$TimeStamp"
            $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
            $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
            $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
            $uri = "https://dapi.binance.com/dapi/v1/account?$QueryString&signature=$signature"
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("X-MBX-APIKEY", $key)
            $result = @()
            $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            $datetime = getLocalTime $TimeStamp
            $newItem = [PSCustomObject]@{
                "accountNum"            = $accountNum
                "exchange"              = $exchange
                "name"                  = $accountName
                "symbol"                = $symbol
                "incomeType"            = $null
                "income"                = $null
                "asset"                 = $null
                "info"                  = $null
                "tranId"                = $null
                "tradeId"               = $null
                "totalWalletBalance"    = ($result.assets | ? {$_.asset -eq $symbol }).walletBalance
                "totalUnrealizedProfit" = ($result.assets | ? {$_.asset -eq $symbol }).unrealizedProfit
                "todayRealizedPnl"      = $null
                "totalRealizedPnl"      = $null
                "source"                = "account"
                "time"                  = [int64] $TimeStamp
                "datetime"              = $datetime
            }
            return $newItem
        }
    }
    elseif ($exchange -eq "bybit") {
        $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $symbol = ($accountSettings | Where-Object { $_.number -eq $accountNum }).symbol
        $QueryString = "api_key=$key&coin=$($symbol)&timestamp=$TimeStamp"
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
        $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
        $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
        $uri = "https://api.bybit.com/v2/private/wallet/balance?$QueryString&sign=$signature"
        # $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($TimeStamp).DateTime)
        $datetime = getLocalTime $TimeStamp
        $result = @()
        $result = Invoke-RestMethod -Uri $uri -Method Get
        $newItem = [PSCustomObject]@{
            "accountNum"            = $accountNum
            "exchange"              = $exchange
            "name"                  = $accountName
            "symbol"                = $symbol + "USD"
            "incomeType"            = $null
            "income"                = $null
            "asset"                 = $null
            "info"                  = $null
            "tranId"                = $null
            "tradeId"               = $null
            "totalWalletBalance"    = $result.result.$symbol.wallet_balance
            "totalUnrealizedProfit" = $result.result.$symbol.unrealised_pnl
            "todayRealizedPnl"      = $result.result.$symbol.realised_pnl
            "totalRealizedPnl"      = $result.result.$symbol.cum_realised_pnl
            "source"                = "account"
            "time"                  = [int64] $TimeStamp
            "datetime"              = $datetime
        }
        if ($newItem.wallet_balance -ne "0") {
            return $newItem
        }
    }
}


function getIncome () {
    Param($accountNum,$startTime)
    $accountSettings = (gc "$($path)\accountData.json"  | ConvertFrom-Json) | ? { $_.enabled -eq "true" }
    $key = ($accountSettings | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accountSettings | Where-Object { $_.number -eq $accountNum }).secret
    $exchange = ($accountSettings | Where-Object { $_.number -eq $accountNum }).exchange
    $accountName = ($accountSettings | Where-Object { $_.number -eq $accountNum }).name
    $symbol = ($accountSettings | Where-Object { $_.number -eq $accountNum }).symbol
    if ($exchange -eq "binance") {
        if (!($symbol)) {
            # https://binance-docs.github.io/apidocs/futures/en/#get-income-history-user_data
            $limit = "1000"    # max 1000
            $results = @()
            while ($true) {
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
                $result = $result | sort time
                $newitems = @()
                foreach ($item in $result) {
                    $datetime = getLocalTime $item.time
                    ### convert commissionAsset to Usd
                    if (($item.incomeType -eq "COMMISSION" -or $item.incomeType -eq "TRANSFER") -and $item.asset -eq "BNB") {
                        $item.income = (getPrice $item.asset $item.time) * ($item.income)
                        $item.asset = "USDT"
                    }
                    $newItem = [PSCustomObject]@{
                        "accountNum"            = $accountNum
                        "exchange"              = $exchange
                        "name"                  = $accountName
                        "symbol"                = $item.symbol
                        "incomeType"            = $item.incomeType
                        "income"                = $item.income
                        "asset"                 = $item.asset
                        "info"                  = $item.info
                        "tranId"                = $item.tranId
                        "tradeId"               = $item.tradeId
                        "totalWalletBalance"    = $null
                        "totalUnrealizedProfit" = $null
                        "todayRealizedPnl"      = $null
                        "totalRealizedPnl"      = $null
                        "source"                = "income"
                        "time"                  = [int64] $item.time
                        "datetime"              = $datetime
                    }
                    $newitems += $newItem
                }
                $results += $newitems
                write-log "downloading, account[$($accountName)] startDate[$($newitems[0].datetime)] results[$($newItems.length)]"
                if ($result.length -lt 1000) { break }
                $startTime = [int64]($result.time | sort)[-1] + 1
            }
            return $results
        }
        else {
            # https://binance-docs.github.io/apidocs/delivery/en/#get-income-history-user_data
            $limit = "1000"    # max 1000
            $results = @()
            while ($true) {
                $result = @()
                $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $QueryString = "&recvWindow=5000&limit=$limit&timestamp=$TimeStamp&startTime=$startTime"
                $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
                $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
                $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
                $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
                $uri = "https://dapi.binance.com/dapi/v1/income?$QueryString&signature=$signature"
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $headers.Add("X-MBX-APIKEY", $key)
                $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                $result = $result | sort time
                $newitems = @()
                foreach ($item in $result) {
                    if ($item.asset -eq $symbol) {
                        $datetime = getLocalTime $item.time
                        ### convert commissionAsset to Usd
                        $newItem = [PSCustomObject]@{
                            "accountNum"            = $accountNum
                            "exchange"              = $exchange
                            "name"                  = $accountName
                            "symbol"                = $item.symbol
                            "incomeType"            = $item.incomeType
                            "income"                = $item.income
                            "asset"                 = $item.asset
                            "info"                  = $item.info
                            "tranId"                = $item.tranId
                            "tradeId"               = $item.tradeId
                            "totalWalletBalance"    = $null
                            "totalUnrealizedProfit" = $null
                            "todayRealizedPnl"      = $null
                            "totalRealizedPnl"      = $null
                            "source"                = "income"
                            "time"                  = [int64] $item.time
                            "datetime"              = $datetime
                        }
                        $newitems += $newItem
                    }
                }
                $results += $newitems
                write-log "downloading, account[$($accountName)] startDate[$($newitems[0].datetime)] results[$($newItems.length)]"
                if ($result.length -lt 1000) { break }
                $startTime = [int64]($result.time | sort)[-1] + 1
            }
            return $results
        }
    }
    elseif ($exchange -eq "bybit") {
        ### https://bybit-exchange.github.io/docs/inverse/#t-walletrecords
        $limit = 50  # max 50
        $results = @()
        $page = 1
        while ($true) {
            $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $startTime1 = ([datetimeoffset]::FromUnixTimeMilliseconds($startTime).DateTime).ToString("yyyy-MM-dd")
            $QueryString = "api_key=$key&currency=$symbol&limit=$limit&page=$page&start_date=$startTime1&timestamp=$TimeStamp"
            $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
            $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
            $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
            $baseUri = "https://api.bybit.com/v2/private/wallet/fund/records"
            $uri = "$($baseUri)?$($QueryString)&sign=$($signature)"
            $result = @()
            $result = Invoke-RestMethod -Uri $uri -Method Get
            if ($result.result.data.length -eq "0") { break }
            $newItems = @()
            foreach ($item in $result.result.data) {
                $time = ([DateTimeOffset]$item.exec_time).ToUnixTimeMilliseconds()
                $datetime = [datetime] $item.exec_time  # converts UTC to local
                if ($item.type -like "*withdraw*") { $item.amount = - $item.amount }
                $newItem = [PSCustomObject]@{
                    "accountNum"            = $accountNum
                    "exchange"              = $exchange
                    "name"                  = $accountName
                    "symbol"                = $item.address
                    "incomeType"            = $item.type
                    "income"                = $item.amount
                    "asset"                 = $item.coin
                    "info"                  = $null
                    "tranId"                = $item.tx_id
                    "tradeId"               = $null
                    "totalWalletBalance"    = $item.wallet_balance
                    "totalUnrealizedProfit" = $null
                    "todayRealizedPnl"      = $null
                    "totalRealizedPnl"      = $null
                    "source"                = "income"
                    "time"                  = [int64] $time
                    "datetime"              = $datetime
                }
                $newItems += $newItem
            }
            $results += $newItems
            write-log "downloading, account[$($accountName)] startDate[$($datetime)] results[$($newItems.length)]"
            $page++
        }
        return $results
    }
}

function addData () {
    $results = @()
    $accountSettings = (gc "$($path)\accountData.json"  | ConvertFrom-Json) | ? { $_.enabled -eq "true" }
    foreach ($account in $accountSettings) {
        $result = @()
        ### get income
        $lastTime = $null
        ### looks for the latest record's datetime for this account
        $Query = 'SELECT max(time) as max_time from Transactions WHERE accountNum = ''' + $account.number + ''' AND source = ''income'''
        $lastTime = [int64] (Invoke-SqliteQuery -DataSource $DataSource -Query $Query).max_time
        ### if last record for this type of record is not found, use the start date from the settings
        if (!($lastTime)) { $lastTime = date2unix $account.start }
        if ($account.exchange -eq "bybit") {
            ### get the time for the midnight of $lastTime
            $midnightDate = ([datetimeoffset]::FromUnixTimeMilliseconds($lastTime).DateTime).Date
            ### convert it to unix time
            $midnightLastTime = ([DateTimeOffset]$midnightDate).ToUnixTimeMilliseconds()
            $Query = 'SELECT * from Transactions WHERE accountNum = ''' + $account.number + ''' AND source = ''income'' AND time >= ' + $($midnightLastTime)
            $old = $new = @()
            $old = Invoke-SqliteQuery -DataSource $DataSource -Query $Query
            $new = getIncome $account.number $lastTime
            ### the following line is supposed to dedupe the results, but doesn't work sometimes, thus the later deduping of the whole db
            [array]$result += ([array]$new | ? { [array]$old -NotContains $_ })
            # $result += ([array]$new + [array]$old) | sort * -uniq
        }
        if ($account.exchange -eq "binance") {
            [array]$result += getIncome $account.number ($lastTime + 1)
        }
        ### get account
        [array]$result += getAccount $account.number
        $results += $result
        write-log "processing,  account[$($account.name)] totalResults[$($result.length)]"
    }
    write-log "Adding results to the database..." -color "Yellow"
    $DataTable = $results | sort time | sort * -uniq | Out-DataTable
    Invoke-SQLiteBulkCopy -DataTable $DataTable -DataSource $DataSource -Table "Transactions" -NotifyAfter 1000 -Confirm:$false
    ### dedupe the db, cuz you know....
    Invoke-SqliteQuery -DataSource $DataSource -Query "DELETE FROM Transactions WHERE rowid NOT IN (SELECT min(rowid) FROM TRANSACTIONS GROUP BY accountNum, exchange, name, symbol, incomeType, income, asset, info, tranId, tradeId, totalWalletBalance, totalUnrealizedProfit, todayRealizedPnl, totalRealizedPnl, source, time, datetime)"
    # $results | sort * -uniq | sort time | ConvertTo-Csv -NoTypeInformation | select -Skip 1 | ac "$($path)\data\data.csv"
}

while ($true) {
    write-log "Checking for new data..." -color "Green"
    addData
    write-log "Import Complete" -color "Green"
    write-log "Sleeping $($refresh) minutes...`n" -color "Cyan"
    betterSleep ($refresh * 60) "AccountData $($version)"
}
