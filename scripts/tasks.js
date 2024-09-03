const { task } = require("hardhat/config");
const path = require("path");
const fse = require("fs-extra");

require('dotenv').config();

const init = async (taskArgs, hre) => {
  const config = {
    network: hre.network.name.toLowerCase(),
    contractName: taskArgs.contractName,
  };
try {
      config.isTestNet = config.network === 'testnet';
      console.log(`\n🏁 Initializing configuration for ${config.contractName} on ${config.network}`);
      config.Contract = await hre.ethers.getContractFactory(`contracts/${config.contractName}.sol:${config.contractName}`);
      return config;
  } catch(e) {
    console.log(`\n🛑 Initialization failed for contracts/${config.contractName}.sol:${config.contractName}`);
    error(config, e);
  }
}

const sleep = async (seconds) => {
  return new Promise(resolve => setTimeout(resolve, seconds * 1000));
}

const updateConfigFile = async(config) => {
  const configPath = path.resolve(__dirname, '..', 'vtru-contracts.json');
  let configData = {};
  if (fse.existsSync(configPath)) {
    configData = fse.readJsonSync(configPath, { spaces: 2});
  }
  // Only update address if called from a task where address changes
  if ('address' in config) {
      configData['mainnet'] = 'mainnet' in configData ? configData['mainnet']: {};
      configData['testnet'] = 'testnet' in configData ? configData['testnet']: {};
      configData[config.network][config.contractName] = config.address;
  }
  configData.abi = 'abi' in configData ? configData.abi : {};
  configData['abi'][config.contractName] = JSON.parse(config.Contract.interface.formatJson());
  fse.writeJSONSync(configPath, configData,{spaces: 2});
  console.log(`\n✅ ${configPath} updated`);
}

const getConfigFile = async() => {
  const configPath = path.resolve(__dirname, '..', 'vtru-contracts.json');
  if (fse.existsSync(configPath)) {
    return fse.readJsonSync(configPath, { spaces: 2});
  } else {
    throw new Error(`\n🛑 ${configPath} file is missing`);
  }
}

const verify = async(config, wait) => {
  if (wait === true) {
    console.log('\n🕦 Waiting for block to be sealed...');
    await sleep(6);  
  }
  try {
    await run("verify:verify", {
      address: config.address,
      constructorArguments: [
      ],
    });  
   console.log(`\n✅ ${config.contractName} verified on ${config.network}`);  
  } catch(e) {
    if (e.message.indexOf('Etherscan API call failed with status 400') < 0) {
       console.log('\n💔', e);
    }
  }
}

const done = () => {
  console.log('\n🙂 DONE!\n\n');
}

const error = (config, e) => {
  console.log('\n💔', e);
  //console.log('\nConfiguration:', config);
}

task("update-abi", "Updates config file ABI for a contract")
.addPositionalParam("contractName")
.setAction(async (taskArgs, hre) => {
  const config = await init(taskArgs, hre);
  try {
    await updateConfigFile(config);
    console.log(`\n✅ ${config.contractName} ABI updated in config file`);  
    done();
  } catch(e) {
    error(config, e);
  }
});

task("verify-contract", "Verify contract on blockchain")
.addPositionalParam("contractName")
.setAction(async (taskArgs, hre) => {
  const configData = await getConfigFile();
  const config = {
    network: hre.network.name.toLowerCase(),
    contractName: taskArgs.contractName,
  }
  config.address = configData[config.network][taskArgs.contractName];

  try {
    await verify(config, false);
    done();
  } catch(e) {
    error(config, e);
  }
});

task("import", "Imports an existing upgradeable contract")
.addPositionalParam("contractName")
.addPositionalParam("address")
.setAction(async (taskArgs, hre) => {
  const config = await init(taskArgs, hre);
  try {
    config.address = taskArgs.address;
    config.instance = await upgrades.forceImport(config.address, config.Contract);
    console.log(`\n✅ ${config.contractName} imported from ${config.network} at ${config.address}`, );  
    await updateConfigFile(config);
    done();
  } catch(e) {
    error(config, e);
  }
});


task("deploy", "Deploy smart contract")
  .addPositionalParam("contractName")
  .setAction(async (taskArgs, hre) => {
    const config = await init(taskArgs, hre);
    try {
      config.instance = await upgrades.deployProxy(config.Contract, {initializer: 'initialize'});
      await config.instance.waitForDeployment();

      config.address = await config.instance.getAddress();
      console.log(`${config.contractName} deployed to ${config.network} at ${config.address} https://${config.isTestNet ? 'test-' : ''}explorer.vitruveo.xyz/address/${config.address}/read-proxy#address-tabs\n\n`, );  
      await updateConfigFile(config);
      await verify(config, true);
      done();
    } catch(e) {
      error(config, e);
    }
  });

  task("upgrade", "Upgrade smart contract")
  .addPositionalParam("contractName")
  .setAction(async (taskArgs, hre) => {
    const config = await init(taskArgs, hre);
    try {
      const configData = await getConfigFile();
      config.address = configData[config.network][config.contractName];
      config.instance = await upgrades.upgradeProxy(config.address, config.Contract, {redeployImplementation: 'always'});
      await config.instance.waitForDeployment();

      console.log(`${config.contractName} upgraded on ${config.network} at ${config.address} https://${config.isTestNet ? 'test-' : ''}explorer.vitruveo.xyz/address/${config.address}/read-proxy#address-tabs\n\n`, );  
      await updateConfigFile(config);
      await verify(config, true);
      done();
    } catch(e) {
      error(config, e);
    }
  });
