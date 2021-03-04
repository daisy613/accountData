# AccountData

![](https://i.imgur.com/RPyoA6H.png)

## What it does:
- This Powershell script continuously downloads all Binance/Bybit income history from multiple accounts into a sqLite db.
- It can be used in tandem with [Darksheer's Crypto-PNL-Tracker](https://github.com/drksheer/Crypto-PNL-Tracker) or on its own.

## Instructions:
1. Specify your settings in the `accountData.json` file
    - **number**: an arbitrary number you want to give to your account (_1, 2, 3, etc_)
    - **exchange**: binance or bybit
    - **name**: an arbitrary number you want to give to your account (_myCoolAccount1_)
    - **key**: your account API key. Best practice is to create a separate Read-Only key for this.
    - **secret**: your account API secret
    - **symbol**: only used for bybit (_BTC, ETH, EOS, etc_)
    - **start**: the day your account was opened
    - **enabled**: true/false
2. Optional: If using [Darksheer's Crypto-PNL-Tracker](https://github.com/drksheer/Crypto-PNL-Tracker), place the files in the root of the tracker.
3. Execute the `accountData.ps1` file from within a Powershell console or by double-clicking on it.
4. Leave it running and it will collect new data every 10 minutes. When each cycle is complete, you will see the green `Import Complete` message.
5. Profit!
6. _Submit any issues or enhancement ideas on the [Issues](https://github.com/daisy613/accountData/issues) page._

## Tips:
- BTC: 1PV97ppRdWeXw4TBXddAMNmwnknU1m37t5
- USDT/ETH (ERC20): 0x56b2239c6bde5dc1d155b98867e839ac502f01ad
- USDT (TRC20): TNuwZebdZmoDxrJRxUbyqzG48H4KRDR7wB (if sending from Binance account - allows for less fees)
