# AccountData

![](https://i.imgur.com/HDahr9a.png)

## What it does:
- This Powershell script continuously downloads all Binance/Bybit income history from multiple accounts into a sqLite db.

## Instructions:
- specify your settings in the accountData.json file
 - **number**: an arbitrary number you want to give to your account (_1, 2, 3, etc_)
 - **exchange**: binance or bybit
 - **name**: an arbitrary number you want to give to your account (_myCoolAccount1_)
 - **key**: your account API key. Best practice is to create a separate Read-Only key for this.
 - **secret**: your account API secret
 - **symbol**: only used for bybit (_BTC, ETH, EOS, etc_)
 - **start**: the day your account was opened
 - **enabled**: true/false
- submit any issues or enhancement ideas on the [Issues](https://github.com/daisy613/accountData/issues) page.

## Tips:
- BTC: 1PV97ppRdWeXw4TBXddAMNmwnknU1m37t5
- ETH  (ERC20): 0x56b2239c6bde5dc1d155b98867e839ac502f01ad
- USDT (TRC20): TNuwZebdZmoDxrJRxUbyqzG48H4KRDR7wB
- USDT (ERC20): 0x56b2239c6bde5dc1d155b98867e839ac502f01ad
