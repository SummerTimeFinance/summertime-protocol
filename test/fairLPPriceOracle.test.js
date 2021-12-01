const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SummerTimeDAO", () => {

  it("Should deploy FairLPPriceOracle contract", async () =>  {
    const FairLPPriceOracleInstance = await ethers.getContractFactory(
      'contracts/FairLPPriceOracle.sol:FairLPPriceOracle'
    );
    const fairLPPriceOracle = await FairLPPriceOracleInstance.deploy();
    await fairLPPriceOracle.deployed();

    // NOTE: You 1st have to add the associated token & their price oracle addresses
    // To be able to fetch the price of each of the related token pairs
    // Add BNB/USD token price oracle
    const addBNBOracle = await fairLPPriceOracle.createOrUpdateTokenPriceOracle(
      '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c', // (token address, chainlink token oracle address)
      '0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE'
    );
    await addBNBOracle.wait();

    // Add CAKE/USD token price oracle
    const addCAKEOracle = await fairLPPriceOracle.createOrUpdateTokenPriceOracle(
      '0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82',
      '0xB6064eD41d4f67e353768aA239cA86f4F73665a1'
    );
    await addCAKEOracle.wait();

    // Now compute the fair LP price for CAKE/BNB LP token
    let getCakeBNBLPPrice = await fairLPPriceOracle.getCurrentFairLPTokenPrice(
      '0x0eD7e52944161450477ee417DE9Cd3a859b14fD0'
    );
    await getCakeBNBLPPrice.wait();

    const CakeBNBLPPrice = await fairLPPriceOracle.getLastKnownFairLPTokenPrice(
      '0x0eD7e52944161450477ee417DE9Cd3a859b14fD0'
    );

    console.log('CAKE-BNB fair LP price: ', CakeBNBLPPrice.toString());
    expect(CakeBNBLPPrice).to.be.an('object');
  })
  .timeout(50000);

});
