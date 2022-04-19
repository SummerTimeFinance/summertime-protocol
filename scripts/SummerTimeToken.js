import { ethers } from 'hardhat';

const main = async () => {
  const summerTimeTokenInstance = await ethers.getContractFactory(
    'contracts/summerTimeToken.sol:summerTimeToken'
  );
  const summerTimeToken = await summerTimeTokenInstance.deploy();

  // The address the contract WILL have once mined
  console.log('Contract address: ', summerTimeToken.address);

  // The transaction that was sent to the network to deploy the Contract
  console.log('Transaction hash: ', summerTimeToken.deployTransaction.hash);

  // Wait for the contract to be deployed
  await summerTimeToken.deployed();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
