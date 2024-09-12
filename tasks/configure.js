const { task } = require("hardhat/config");
const chainsConfig = require('@vialabs-io/contracts/config/chains');

const networks = [
    "mainnet",
    "ethereum",
    "base",
    "bsc",
    "polygon",
    "avalanche"
];

const chainids = [
	1490,
	1,
	8453,
	56,
	137,
	43114
]

// const messages = {
// 	"1490": "0x15AC559DA4951c796DB6620fAb286B96840D039A",
// 	"1": "0x7b67dF6728E294db2eb173ac7c738a4627Ae5e11",
// 	"8453": "0xe3b3274bb685F37C7f17a604039c77a6A16Cfc2a",
// 	"56": "0x7b67dF6728E294db2eb173ac7c738a4627Ae5e11",
// 	"137": "0x1C5800eb5fECB7760D7F1978ad744feA652a7b27",
// 	"43114": "0x72E052Fa7f0788e668965d37B6c38C88703B7859"
// }

const addresses = [
	'0x4D5B24179c656A88087eF4369887fD58AB5e8EF3',
	'0x3153F488233132c429175b5FD8199eb775b6C6Ff',
	'0x6793c3172DacaE034B3e84909E200DB285225AB3',
	'0x6793c3172DacaE034B3e84909E200DB285225AB3',
	'0x6793c3172DacaE034B3e84909E200DB285225AB3',
	'0x30d414eab3575ff4bF1Ea2c63401BA1D22De231f'
]

const confirmations = [
	1,
	1,
	1,
	1,
	1,
	1
]

task("configure", "")
	.addOptionalParam("signer", "Custom signer (private key)")
	.addOptionalParam("provider", "Custom provider RPC url")
	.setAction(async (args, hre) => {
		const ethers = hre.ethers;
		const [deployer] = await ethers.getSigners();

		let signer = deployer;
		if (args.signer) signer = new ethers.Wallet(args.signer, new ethers.providers.JsonRpcProvider(args.provider));
			console.log(hre.network.config.chainId)
		console.log('setting remote contract addresses .. CLT message address:', chainsConfig[hre.network.config.chainId].message);
		//const veo = await ethers.getContract("VEO");
		//await (await veo.configureClient(chainsConfig[hre.network.config.chainId].message, chainids, addresses, confirmations)).wait();
	});
