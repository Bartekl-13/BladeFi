# BladeFi

## A simplified perpetuals DeFi protocol.

--- 

### How does it work?

BladeFi is a perpetuals protocol, which allows users (traders) to use leverage for their long/short positions.
</br>
The liquidity in the protocol is provided by LPs - liquidity providers, who earn share tokens with a ratio 1:1 to supplied tokens.
</br>
In this simplified implementation of a protocol, no fees or P&L payouts are calculated.
</br>
The realtime value of liquidity pools and open interest are tracked, to ensure no money meant for a beneficiary of a successful trade is taken out of the system before payout.

---

### How to use it?

#### For LPs

You can deposit and later withdraw your liquidity.</br>

#### For Traders

After providing collateral in USDC, you are eligible to borrow assets. </br>
The leverege on your borrowed tokens must not exceed 20x. </br>

Otherwise, liquidation will occur to ensure the debt cannot be larger tham the collateral.
