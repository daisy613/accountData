### for bybit, neet to add specify symbol, like BTC, ETH, etc.
$accounts = @(
        [PSCustomObject]@{ "number" = "1"; "exchange" = "binance"; "name" = "xxx"; "key" = "xxx"; "secret" = "xxx" ; symbol = "" },
        [PSCustomObject]@{ "number" = "2"; "exchange" = "binance"; "name" = "xxx"; "key" = "xxx"; "secret" = "xxx" ; symbol = "" },
        [PSCustomObject]@{ "number" = "3"; "exchange" = "binance"; "name" = "xxx"; "key" = "xxx"; "secret" = "xxx" ; symbol = "" },
        [PSCustomObject]@{ "number" = "4"; "exchange" = "bybit"; "name" = "xxx"; "key" = "xxx"; "secret" = "xxx" ; symbol = "BTC" }
    )

function getLocalTime {
    param( [parameter(Mandatory = $true)] [String] $UTCTime )
    $strCurrentTimeZone = (Get-WmiObject win32_timezone).StandardName
    $TZ = [System.TimeZoneInfo]::FindSystemTimeZoneById($strCurrentTimeZone)
    $LocalTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($UTCTime, $TZ)
    return $LocalTime
}

### get symbols
function getSymbolsBinance () {
    $exchangeInfo = "https://fapi.binance.com/fapi/v1/exchangeInfo"
    $symbols = ((Invoke-RestMethod -Uri $exchangeInfo).symbols).symbol | Sort-Object
    return $symbols
}

### get account info
function getAccount () {
    Param(
        [Parameter(Mandatory = $false, Position = 0)]$accountNum
    )
    $exchange = ($accounts | Where-Object { $_.number -eq $accountNum }).exchange
    $accountName = ($accounts | Where-Object { $_.number -eq $accountNum }).name
    $key = ($accounts | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accounts | Where-Object { $_.number -eq $accountNum }).secret
    $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($exchange -eq "binance") {
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
        $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($TimeStamp).DateTime)
        $newItem = [PSCustomObject]@{
            "exchange"              = $exchange
            "name"                  = $accountName
            "symbol"                = ""
            "totalWalletBalance"    = $result.totalWalletBalance
            "totalUnrealizedProfit" = $result.totalUnrealizedProfit
            "realizedPnl"           = ""
            "totalRealizedPnl"      = ""
            "time"                  = $TimeStamp
            "datetime"              = $datetime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        return $newItem
    }
    elseif ($exchange -eq "bybit") {
        # $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $symbol = ($accounts | Where-Object { $_.number -eq $accountNum }).symbol
        $QueryString = "api_key=$key&timestamp=$TimeStamp"
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
        $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
        $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
        $uri = "https://api.bybit.com/v2/private/wallet/balance?$QueryString&sign=$signature"
        $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($TimeStamp).DateTime)
        $result = @()
        $result = Invoke-RestMethod -Uri $uri -Method Get
        $newItem = [PSCustomObject]@{
            "exchange"              = $exchange
            "name"                  = $accountName
            "symbol"                = $symbol
            "totalWalletBalance"    = $result.result.$symbol.wallet_balance
            "totalUnrealizedProfit" = $result.result.$symbol.unrealised_pnl
            "realizedPnl"           = $result.result.$symbol.realised_pnl
            "totalRealizedPnl"      = $result.result.$symbol.cum_realised_pnl
            "time"                  = $TimeStamp
            "datetime"              = $datetime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        if ($newItem.wallet_balance -ne "0") {
            return $newItem
        }
    }
}

function getOrders () {
    Param([Parameter(Mandatory = $false, Position = 0)]$accountNum,
          [Parameter(Mandatory = $false, Position = 1)]$startTime,
          [Parameter(Mandatory = $false, Position = 2)]$symbol,
          [Parameter(Mandatory = $false, Position = 3)]$fromId
    )
    $key = ($accounts | Where-Object { $_.number -eq $accountNum }).key
    $secret = ($accounts | Where-Object { $_.number -eq $accountNum }).secret
    $exchange = ($accounts | Where-Object { $_.number -eq $accountNum }).exchange
    $accountName = ($accounts | Where-Object { $_.number -eq $accountNum }).name
    if ($exchange -eq "binance") {
        # https://binance-docs.github.io/apidocs/futures/en/#account-trade-list-user_data
        $limit = "1000"    # max 1000
        $results = @()
        while ($true) {
            $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $QueryString = "&recvWindow=5000&limit=$limit&timestamp=$TimeStamp&symbol=$symbol&fromId=$fromId&startTime=$startTime"
            $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
            $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
            $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
            $baseUri = "https://fapi.binance.com/fapi/v1/userTrades"
            $uri = "$($baseUri)?$($QueryString)&signature=$($signature)"
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("X-MBX-APIKEY", $key)
            $result = @()
            $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            foreach ($item in $result) {
                $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($item.time).DateTime)
                $newItem = [PSCustomObject]@{
                    "exchange"        = $exchange
                    "name"            = $accountName
                    "symbol"          = $symbol
                    "id"              = $item.id
                    "orderId"         = $item.orderId
                    "side"            = $item.side
                    "price"           = $item.price
                    "qty"             = $item.qty
                    "realizedPnl"     = $item.realizedPnl
                    "marginAsset"     = $item.marginAsset
                    "quoteQty"        = $item.quoteQty
                    "commission"      = $item.commission
                    "commissionAsset" = $item.commissionAsset
                    "time"            = $item.time
                    "positionSide"    = $item.positionSide
                    "maker"           = $item.maker
                    "buyer"           = $item.buyer
                    "datetime"        = $datetime
                }
                # $newItem | select symbol,orderId,time,datetime
                $results += $newItem
            }
            if ($result.length -lt 1000) { break }
            $startTime =  [int64]($result.time | sort)[-1] + 1
        }
        return $results
    }
    elseif ($exchange -eq "bybit") {
        ### https://bybit-exchange.github.io/docs/inverse/#t-closedprofitandloss
        # $symbol = ($accounts | Where-Object { $_.number -eq $accountNum }).symbol
        $symbol = $symbol + "USD"
        $limit = 50  # max 50
        $results = @()
        $page = 1
        while ($true) {
            $TimeStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $QueryString = "api_key=$key&limit=$limit&page=$page&start_time=$startTime&symbol=$symbol&timestamp=$TimeStamp"
            $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
            $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($QueryString))
            $signature = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
            $baseUri = "https://api.bybit.com/v2/private/trade/closed-pnl/list"
            $uri = "$($baseUri)?$($QueryString)&sign=$($signature)"
            $result = @()
            $result = Invoke-RestMethod -Uri $uri -Method Get
            if (!($result.result.data)) {break}
            foreach ($item in $result.result.data) {
                $datetime = getLocalTime ([datetimeoffset]::FromUnixTimeMilliseconds($item.created_at * 1000).DateTime)
                $newItem = [PSCustomObject]@{
                    "exchange"        = $exchange
                    "name"            = $accountName
                    "symbol"          = $symbol
                    "id"              = ""
                    "orderId"         = $item.order_id
                    "side"            = $item.side
                    "price"           = $item.order_price
                    "qty"             = $item.qty
                    "realizedPnl"     = $item.closed_pnl
                    "marginAsset"     = ""
                    "quoteQty"        = ""
                    "commission"      = ""
                    "commissionAsset" = ""
                    "time"            = $item.created_at
                    "positionSide"    = ""
                    "maker"           = ""
                    "buyer"           = ""
                    "datetime"        = $datetime
                }
                $results += $newItem
            }
            $page++
        }
        return $results
    }
}

# getOrders 4 | select exchange,realizedPnl,time,datetime | sort time
# getOrders 1 "1611605557762" "DOGEUSDT" | select exchange,realizedPnl,time,datetime | sort time

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
    $dataRoot = "E:\BOTS\Zacct\data"
    foreach ($account in $accounts) {
        $file = "$($dataRoot)\data_orders$($account.number).csv"
        $lastTime = $null
        if ($account.exchange -eq "binance") {
            $symbols = getSymbolsBinance
        }
        elseif ($account.exchange -eq "bybit") {
            $symbols = @($account.symbol)
        }
        $orders = @()
        foreach ($symbol in $symbols) {
            $results = @()
            $result = @()
            $lastTime = $null
            $lastTime = [int64]((gc $file -tail 1).split(",")[13] -replace '"','') + 1
            $result = getOrders $account.number $lastTime $symbol
            $results += $result
            write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]`tOrders`t`t`t`t$($symbol):`t$($result.length)" -ForegroundColor Blue
        }
        write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]`tOrders`taccount: $($account.number)`t$($symbol):`t$($result.length)" -ForegroundColor Green
        $orders += $results
    }
    $orders | sort -uniq -property id | sort time | ConvertTo-Csv -NoTypeInformation | select -Skip 1 | ac $file
}

function addIncome () {
    $dataRoot = "E:\BOTS\Zacct\data"
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
