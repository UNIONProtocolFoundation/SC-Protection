// migrations/2_deploy_box.js
const UnionSCPool = artifacts.require('UnionSCPool');
const SCProtections = artifacts.require('SCProtections');
const SCPClaims = artifacts.require('SCPClaims');
const UpgradeableBeacon = artifacts.require('UpgradeableBeacon');
const BeaconProxy = artifacts.require('BeaconProxy');
// const uUNNToken = artifacts.require('AccessControlUpgradeable');
const UnionRouter = artifacts.require('UnionRouter');
const uUNNToken = artifacts.require('uUNNToken');
const UniswapUtil = artifacts.require('UniswapUtil');
const TestToken = artifacts.require('TestToken');
const EthCrypto = require("eth-crypto");

function toBN(number) {
  return web3.utils.toBN(number);
}

const decimals = toBN('10').pow(toBN('18'));

function printEvents(txResult, strdata){
  console.log(strdata," events:",txResult.logs.length);
  for(var i=0;i<txResult.logs.length;i++){
      let argsLength = Object.keys(txResult.logs[i].args).length;
      console.log("Event ",txResult.logs[i].event, "  length:",argsLength);
      for(var j=0;j<argsLength;j++){
          if(!(typeof txResult.logs[i].args[j] === 'undefined') && txResult.logs[i].args[j].toString().length>0)
              console.log(">",i,">",j," ",txResult.logs[i].args[j].toString());
      }
  }

}
 
module.exports = async function (deployer, network, accounts) {
  let signatureWallet = '0x84a5B4B863610989197C957c8816cF6a3B91adD2';
  let usdcAddress;
  let uuNNTokenAddress;
  let router;
  if(network == 'rinkeby' || network == 'rinkeby-fork'){
    usdcAddress = '0x3813a8Ba69371e6DF3A89b78bf18fC72Dd5B43c5';
    router = await UnionRouter.at('0x70CBfC1B9E9E50B84b5E8074692ccCbd98a7146e');

  }else if(network == 'ropsten'){
    daiTokenAddress = '0x7D8AB70Da03ef8695c38C4AE3942015c540e2439';
    daiEthChainlinkFeed = '0x74825DbC8BF76CC4e9494d0ecB210f676Efa001D';
    btcUsdChainlinkFeed = '0xECe365B379E1dD183B20fc5f022230C044d51404';
  }
  else if(network == 'test' || network =='mainnet'){
    usdcAddress = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
    
    await deployer.deploy(UnionRouter).then(function(instance){
      router = instance;
    });
    await router.initialize.sendTransaction(accounts[0]);

    let uUNNTokenInstance;
    await deployer.deploy(uUNNToken).then(function(){
      return UpgradeableBeacon.new(uUNNToken.address);
    }).then(function (Beacon){
      console.log ("uUNNToken Beacon:", Beacon.address);
      return BeaconProxy.new(Beacon.address, web3.utils.hexToBytes('0x'));
    }).then (function(BeaconProxy){
      return uUNNToken.at(BeaconProxy.address);
    }).then(function (instance){
      uUNNTokenInstance = instance;
    });
    console.log ("uUNNToken Proxy Instance:", uUNNTokenInstance.address);
    await uUNNTokenInstance.initialize.sendTransaction(accounts[0]);
    await router.setUUNNToken.sendTransaction(uUNNTokenInstance.address, {from: accounts[0]});
  }

  let scPoolInstance;
  await deployer.deploy(UnionSCPool).then(function(){
    return UpgradeableBeacon.new(UnionSCPool.address);
  }).then(function (Beacon){
    console.log ("UnionSCPool Beacon:", Beacon.address);
    return BeaconProxy.new(Beacon.address, web3.utils.hexToBytes('0x'));
  }).then (function(BeaconProxy){
    return UnionSCPool.at(BeaconProxy.address);
  }).then(function (instance){
    scPoolInstance = instance;
  });
  console.log ("UnionSCPool Proxy Instance:", scPoolInstance.address);

  let scProtecionsInstance;
  await deployer.deploy(SCProtections).then(function(){
    return UpgradeableBeacon.new(SCProtections.address);
  }).then(function (Beacon){
    console.log ("SCProtections Beacon:", Beacon.address);
    return BeaconProxy.new(Beacon.address, web3.utils.hexToBytes('0x'));
  }).then (function(BeaconProxy){
    return SCProtections.at(BeaconProxy.address);
  }).then(function (instance){
    scProtecionsInstance = instance;
  });
  console.log ("SCProtections Proxy Instance:", scProtecionsInstance.address);

  let scClaims;
  await deployer.deploy(SCPClaims).then(function(){
    return UpgradeableBeacon.new(SCPClaims.address);
  }).then(function (Beacon){
    console.log ("SCPClaims Beacon:", Beacon.address);
    return BeaconProxy.new(Beacon.address, web3.utils.hexToBytes('0x'));
  }).then (function(BeaconProxy){
    return SCPClaims.at(BeaconProxy.address);
  }).then(function (instance){
    scClaims = instance;
  });
  console.log ("SCPClaims Proxy Instance:", scClaims.address);

  let uUNNTokenAddress = await router.uunnToken.call();
  console.log("uUNNTokenAddress", uUNNTokenAddress);

  //init SCProtections and SCPClaims
  await scProtecionsInstance.initialize.sendTransaction(accounts[0], uUNNTokenAddress, scClaims.address, {from: accounts[0]});
  await scClaims.initialize.sendTransaction(accounts[0], scProtecionsInstance.address, {from: accounts[0]});
  let uUNNTokenInstance = await uUNNToken.at(uUNNTokenAddress);
  await uUNNTokenInstance.grantRole.sendTransaction(web3.utils.keccak256('PROTECTION_FACTORY_ROLE'), scProtecionsInstance.address);
  await scProtecionsInstance.grantRole.sendTransaction(web3.utils.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signatureWallet);
  
  if(network == 'test') {
    await router.setAddress(toBN(20010),scProtecionsInstance.address);
    await router.setAddress(toBN(20011),scClaims.address);
  }
};