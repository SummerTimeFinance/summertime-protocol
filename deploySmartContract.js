require('./env.js');
const fs = require('fs');
const path = require('path');
const Web3 = require('web3');
const connectedEthBlockchain = new Web3(process.env.ENDPOINT);

const allFilesInBuildFolder = fs.readdirSync(path.join(__dirname, 'build'), {
  withFileTypes: true,
});
const [smartContractABIFile, smartContractByteCodeFile] = allFilesInBuildFolder.filter(
	(file) => file.isFile || file.includes('.abi') || file.includes('.bin')
);
const smartContractABI = JSON.parse(fs.readFileSync(`./build/${smartContractABIFile.name}`));
const smartContractByteCode = fs.readFileSync(`./build/${smartContractByteCodeFile.name}`);

(async function () {
	let ethereumAddressToDeployFrom;
	const connectedEthBlockchainAddresses = await connectedEthBlockchain.eth.getAccounts();
	if (connectedEthBlockchainAddresses.length) {
		ethereumAddressToDeployFrom = connectedEthBlockchainAddresses[0];
	}

	// if one has been provided, override the on provided from Ganache
	if (process.env.ETHEREUM_ADDRESS) {
		ethereumAddressToDeployFrom = process.env.ETHEREUM_ADDRESS;
	}

	if (!smartContractABI) {
		throw new Error('Missing smart contract ABI');
	}

	if (!smartContractByteCode) {
		throw new Error('Missing smart contract byte code');
	}

  const theSmartContract = new connectedEthBlockchain.eth.Contract(smartContractABI);
	theSmartContract
		.deploy({ data: smartContractByteCode })
		.send({ from: ethereumAddressToDeployFrom, gas: 5000000 })
		.then((deployment) => {
			const [smartContractABIFileName] = (`./build/${smartContractABIFile.name}`).split('/').reverse();
			const [smartContractName] = smartContractABIFileName.split('.');
			const smartContractFileName = [smartContractName, '.sol'].join('');
			console.log(`${ smartContractFileName || 'Smart contract' } was successfully deployed!`);
			console.log(`${ smartContractFileName || 'Smart contract' } can be interfaced with at this address:`);
			console.log(`Address: ${deployment.options.address}`);
		})
		.catch((err) => {
			console.error(err);
		});
})();
