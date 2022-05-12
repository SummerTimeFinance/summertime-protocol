## Getting SummerTime Protocol to work

Initial requirements:
- SummerTime performance fee collecting address
- SummerTime buyback fee collecting address

Dependencies to deploy this order:

- SimpleInterestModel

- $SUMMER token deployment

- FairLPPriceOracle
    - Once deployed, add 2 tokens to be monitored. CAKE and BNB.

Once FairLPPriceOracle is deployed, add oracles for the respective pairs.
 - CAKE token address & oracle: 0x81faeDDfeBc2F8Ac524327d70Cf913001732224C
 - WBNB token address & oracle: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526

- FarmingStrategy
    - SUMMER token address
    - CAKE token address
    - PCS MasterChef address
    - PCS Uniswap router address
    - SummerTime performance fee collecting address
    - SummerTime buyback fee collecting address

Deployment argument (in remixd)
=> 0x73d456b91989658b94FD11177837e178Da3B5171,0xFa60D973F7642B748046464e165A65B7323b0DEE,0xB4A466911556e39210a6bB2FaECBB59E4eB7E43d,0xD99D1c33F9fC3444f8101754aBC46c52416550D1,0x6505fD2C8Ea0c633C3Dd0636a66788b21f7c01C9,0x3022cA228B07Cd021E940ED9b19d75f71a08bf2F


- SummerTimeCore
Deployment argument (in remixd)
=> 0xE497c0d37F1F916d4c7caddAbCe2D2b1fc7b7a11,0x0f84272629eF566D55de445Af8E199A743dF70cB,0x87482a7d54fefA7d70B90C8Dd945EF789630833f


The following collateral addresses will be supported (progressively):
- BTCB-ETH (old is gold, proven) [127M]
- BTCB-BUSD [118M]
- ETH-BNB [139M]
- BTCB-BNB [118M]
- BUSD-BNB [460M]
- USDT-BNB [230M]
- CAKE-BNB (has largest liquidity) [600M]
- Stablecoin LPs:
- USDC-BUSD [122M]
- USDT-BUSD [289M]
- USDC-USDT [90M]

Total addressable market size: $2.2B (BSC, using PancakeSwap only) 
