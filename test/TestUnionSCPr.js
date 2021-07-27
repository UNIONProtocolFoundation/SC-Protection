const UnionSCPool = artifacts.require("UnionSCPool");
const uUNNToken = artifacts.require("uUNNToken");
const UnionRouter = artifacts.require("UnionRouter");
const UpgradeableBeacon = artifacts.require("UpgradeableBeacon");
const TestToken = artifacts.require("TestToken");
const SCProtections = artifacts.require("SCProtections");
const BeaconProxy = artifacts.require('BeaconProxy');
const SCPClaims = artifacts.require("SCPClaims");
const UniswapUtil = artifacts.require("UniswapUtil");
const EthCrypto = require("eth-crypto");
const {expectRevert, time} = require("openzeppelin-test-helpers");
const {assert, expect} = require("chai");
const {MAX_UINT256} = require("openzeppelin-test-helpers/src/constants");
// const { time, expectRevert } = require('@openzeppelin/test-helpers');
const { web3 } = require("openzeppelin-test-helpers/src/setup");
const constants = require("openzeppelin-test-helpers/src/constants");
const SECONDS_IN_DAY = 86400;

const daiTokenAddress = '0x6b175474e89094c44da98b954eedeac495271d0f';
const wETHtoken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

const uniswapRouterAddress = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

function toBN(number){
    return web3.utils.toBN(number);
}

const decimals = toBN('10').pow(toBN('18'));

function printEvents(txResult, strdata) {
    console.log(strdata, " events:", txResult.logs.length);
    for (var i = 0; i < txResult.logs.length; i++) {
        let argsLength = Object.keys(txResult.logs[i].args).length;
        console.log("Event ", txResult.logs[i].event, "  length:", argsLength);
        for (var j = 0; j < argsLength; j++) {
            if (!(typeof txResult.logs[i].args[j] === 'undefined') && txResult.logs[i].args[j].toString().length > 0)
                console.log(">", i, ">", j, " ", txResult.logs[i].args[j].toString());
        }
    }
}

const buyDAI = async (uniswapUtil, account) => {
    await uniswapUtil.buyExactTokenWithEth.sendTransaction(daiTokenAddress, account, {
        from: account,
        value: toBN(2).mul(decimals)});
        let balanceDAI = await daiToken.balanceOf.call(account);
        // console.log("DAI balance : ", balanceDAI.toString());
        assert.notEqual(balanceDAI.toString(), '0');
}

const approveToken = async (token, owner, spender) => {
    await token.approve(spender, MAX_UINT256, { from: owner });
}

const buyProtection = async (
    scProtectionSeller, ardata, signature, 
    deadline, buyerAccount ) => {
    let buyRes = await scProtectionSeller.create.sendTransaction(ardata, signature, deadline, {
        from: buyerAccount });
    return buyRes;
}

const withdrawWithData = async (pool, requestID, amount, 
    ardata, signature, account) => {
    let withdrawRes = pool.withdrawWithData(requestID, amount, ardata, signature,{
        from:account
    });
    return withdrawRes;
    }

const signMessage = async (message, privateKey) =>{
    const publicKey = EthCrypto.publicKeyByPrivateKey(privateKey);
    const signerAddress = EthCrypto.publicKey.toAddress(publicKey);
    const messageHash = EthCrypto.hash.keccak256(message);
    const signature = EthCrypto.sign(privateKey, messageHash);
    return signature; 
}

const showClaimData = async (claimData) =>{
    console.log('Claim status: ', claimData[0].toString());
    console.log('Payout percent applied: ', claimData[1].toString());
    console.log('Amount of claimers that attempted to fill the claim: ', claimData[2].toString());
    console.log('Claim reference pool: ', claimData[3].toString());
    console.log('Last status update timestamp: ', claimData[4].toString()); 
}
const showProtectionData = async (protectionData) => {
  console.log('Protecion pool: ', protectionData[0].toString());
  console.log('ppID: ', protectionData[1].toString());
  console.log('Amount: ', protectionData[2].toString());
  console.log('Premium: ', protectionData[3].toString());
  console.log('Valid to: ', protectionData[5].toString());
}
async function printPoolStat(pool) {
    let poolStat = await pool.getPoolStat.call();
    console.log("Pool stat: ");
    console.log("totalCap: ", poolStat[0].toString());
    console.log("totalSupply: ", poolStat[1].toString());
    console.log("lockedPremium: ", poolStat[2].toString());
    console.log("mcr: ", poolStat[3].toString());
    console.log("totalMcrPending: ", poolStat[4].toString());
    console.log("mcrUpdatedBlockNumber: ", poolStat[5].toString());
    console.log("mcrPendingsList.sizeOF(): ", poolStat[6].toString());
}

let accounts;
let daiToken;
let scProtections;
let signatureWallet = "0x84a5B4B863610989197C957c8816cF6a3B91adD2";
let uunnToken;
let uunnTokenBeacon;
let uniswapUtil;
let uUNNTokenInstance;
let unionDAIPool;
let scProtectionSeller;
let scpClaimsInstance;
let adminAddress;
let claimManager; 

let timestamp;
let ppID = EthCrypto.hash.keccak256('example');

const deployNewPool = async () => {
    const unionSCPool = await UnionSCPool.new();
    const unionSCPoolBeacon = await UpgradeableBeacon.new(unionSCPool.address);
    const beaconProxy = await BeaconProxy.new(unionSCPoolBeacon.address, web3.utils.hexToBytes('0x'));
    const newPool = await UnionSCPool.at(beaconProxy.address);
    return newPool;
}


const deployContract = async () => {
    unionDAIPool = await deployNewPool();
    uunnToken = await uUNNToken.new();
    uunnTokenBeacon = await UpgradeableBeacon.new(uunnToken.address);
    console.log("uUNNTokenBeacon: ", uunnTokenBeacon.address);
    const uunnTokenBeaconProxy = await BeaconProxy.new(uunnTokenBeacon.address, web3.utils.hexToBytes('0x'));
    uUNNTokenInstance = await uUNNToken.at(uunnTokenBeaconProxy.address);
    console.log("uUNNToken Proxy Instance:", uunnTokenBeaconProxy.address);
    await uUNNTokenInstance.initialize(accounts[0]);
    let SCProtectionsBeaconProxy;
    let scProtectionsInstance;
    scProtections = await SCProtections.new();
    const scProtectionsBeacon = await UpgradeableBeacon.new(scProtections.address);
    SCProtectionsBeaconProxy = await BeaconProxy.new(scProtectionsBeacon.address, web3.utils.hexToBytes('0x'));
    scProtectionsInstance = await SCProtections.at(SCProtectionsBeaconProxy.address);
    let SCPClaimsBeaconProxy;
    // let scpClaimsInstance;
    scpClaims = await SCPClaims.new();
    const scpClaimsBeacon = await UpgradeableBeacon.new(scpClaims.address);
    SCPClaimsBeaconProxy = await BeaconProxy.new(scpClaimsBeacon.address, web3.utils.hexToBytes('0x'));
    scpClaimsInstance = await SCPClaims.at(SCPClaimsBeaconProxy.address);
    scpClaimsInstance.initialize(accounts[0], SCProtectionsBeaconProxy.address);
    await scProtectionsInstance.initialize(accounts[0], uunnTokenBeaconProxy.address, SCPClaimsBeaconProxy.address);
    // address admin, address _basicToken, bytes32 _ppID, address _scProtectionStorage, string memory _description
    await unionDAIPool.initialize(accounts[0], daiTokenAddress, ppID, SCProtectionsBeaconProxy.address, 'DAI Pool');
    
    unionRouter = await UnionRouter.new();
    await unionRouter.initialize(accounts[0]);
    
    // await unionRouter.addCollateralProtection(wETHtoken, unionDAIPool.address, SCProtectionsBeaconProxy.address);
    await unionRouter.addCollateralProtection(daiTokenAddress, unionDAIPool.address, SCProtectionsBeaconProxy.address);
    await unionRouter.setUUNNToken(uunnTokenBeaconProxy.address);
    
    //grantRole
    await uUNNTokenInstance.grantRole(EthCrypto.hash.keccak256('PROTECTION_FACTORY_ROLE'), SCProtectionsBeaconProxy.address);
    await scProtectionsInstance.grantRole(EthCrypto.hash.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signatureWallet);
    await unionDAIPool.grantRole(EthCrypto.hash.keccak256('MCR_PROVIDER'), signatureWallet);
    // await scpClaimsInstance.grantRole(EthCrypto.hash.keccak256('CLAIM_MANAGER'), signatureWallet);
    await scpClaimsInstance.grantRole(EthCrypto.hash.keccak256('CLAIM_MANAGER'), claimManager);
}

const deposit = async (pool, account, amount) => {
    const res = await pool.deposit.sendTransaction(amount, {from:account});
    return res; 
}

describe('UnionSCPool', function() {
    this.timeout(30000);
  
    before(async () => {
        // this.timeout(40000);
        accounts = await web3.eth.getAccounts();
        assert.isAtLeast(accounts.length, 10, 'User accounts must be at least 10');
        adminAddress = accounts[0];
        claimManager = accounts[0];
        daiToken = await TestToken.at(daiTokenAddress);
        await deployContract();
        let daiRes = await unionRouter.collateralProtection.call(daiTokenAddress);
        unionDAIPool = await UnionSCPool.at(daiRes[1]);
        scProtectionSeller = await SCProtections.at(daiRes[0]);
        await scProtectionSeller.grantRole(EthCrypto.hash.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signatureWallet);
        await scProtectionSeller.setActiveSCProtectionPoolAddress(ppID, unionDAIPool.address);
        console.log('unionDAIPool: ', unionDAIPool.address); 
        await UniswapUtil.new(uniswapRouterAddress, {from:accounts[0]})
            .then(instance => uniswapUtil = instance);
        // timestamp = toBN(86400).mul(toBN(1000));
    });


it('should get some DAI', async() => {
    // console.log('accounts[1] : ', accounts[1]);
    for(let i = 1; i < 10; i++){
        await buyDAI(uniswapUtil, accounts[i]);
    }
});

it('should push liquidity into Pools', async () =>{
    for (let i = 4; i < 10; i++){
        let balanceDAI = await daiToken.balanceOf.call(accounts[i]);
        await approveToken(daiToken, accounts[i], unionDAIPool.address);
        await deposit(unionDAIPool, accounts[i], balanceDAI);
        var writerData = await unionDAIPool.getWriterDataExtended(accounts[i]);
        console.log("User stat", writerData[0].toString(), writerData[1].toString(), writerData[2].toString());
    }

    let ethPoolBalance = await unionDAIPool.getTotalValueLocked();
    console.log('unionDAIPool stat: ', ethPoolBalance[0].toString(), ' ', ethPoolBalance[1].toString());
});

it('should buy protection', async () =>{
    let buyerAccount = accounts[2];
    // let buyerAccount = signatureWallet;

    // create(uint256[9] memory data, bytes memory signature, uint256 deadline)
    //         data[0] = tokenid - protection ERC721 token identifier (UUID)
    // *       data[1] = premium - amount of premium tokens to be transferred to pool (protection cost)
    // *       data[2] = validTo - protection validTo parameter, timestamp (protection will be valid until this timestamp)
    // *       data[3] = amount - the underlying protected asset amount (with appropriate decimals)
    // *       data[4] = poolAddress - address of the underlying pool, that will be backing the protection
    // *       data[5] = mcr - MCR value as of mcrBlockNumber
    // *       data[6] = mcrBlockNumber - a block number MCR was calculated for
    // *       data[7] = mcrIncrement - an MCR increment. The amount of capital has to be reserved under MCR to cover this individual protection (that will be issued within transaction)
    // *       data[8] = deadline - operation deadline, timestamp in seconds
    
    let validTo = new Date().getTime() + (2 *24 * 60 * 60 * 1000);
    let premium = toBN(5).mul(decimals);
    let tokenId = toBN(1);
    let amount = toBN(10).mul(decimals);
    let mcr = toBN(1000).mul(decimals);
    let mcrIncrement = toBN(200).mul(decimals);
    // let poolAddress = toBN(unionDAIPool.address);
    let poolAddress = unionDAIPool.address;
    let block = await web3.eth.getBlock("latest");
    let mcrBlockNumber = block.number;
    let deadline = Math.round((new Date().getTime() + ( 1 * 24 * 60 * 60 * 1000 )) / 1000);
    console.log('poolAddress : ', poolAddress.toString());
    let dataArr = [tokenId, premium, validTo, amount, poolAddress, mcr, mcrBlockNumber, mcrIncrement, deadline];
    // console.log("Basic pool token: ", await unionDAIPool.getBasicToken().toString());
    //
    const privateKey = "e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178"; 
    //
    let message = [
    {
        type: "uint256",
        value: tokenId.toString()
    },
    {
        type: "uint256",
        value: premium.toString()
    },
    {
        type: "uint256",
        value: validTo.toString()
    },
    {
        type: "uint256",
        value: amount.toString()
    },
    {
        type: "uint256",
        value: poolAddress.toString()
    },
    {
        type: "uint256",
        value: mcr.toString()
    },
    {
        type: "uint256",
        value: mcrBlockNumber.toString()
    },
    {
        type: "uint256",
        value: mcrIncrement.toString()
    },
    {
        type: "uint256",
        value: deadline.toString()
    }];
    const signature = await signMessage(message, privateKey);
    const publicKeySigner = EthCrypto.publicKeyByPrivateKey(privateKey);
    const signerAddress = EthCrypto.publicKey.toAddress(publicKeySigner);
    let allowed = await scProtectionSeller.hasRole(web3.utils.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signerAddress);
    assert.equal(allowed, true, 'Signer account is not PROTECTION_PREMIUM_DATA_PROVIDER');
    
    
    let daiBalanceBefore = await daiToken.balanceOf.call(buyerAccount);
    let poolBalanceBefore = await daiToken.balanceOf.call(unionDAIPool.address);
    console.log('daiBalanceBefore: ', daiBalanceBefore.toString());
    await approveToken(daiToken, buyerAccount, scProtectionSeller.address);
    //buy protection
    let buyResult = await buyProtection(scProtectionSeller, dataArr, signature, deadline, buyerAccount);
    printEvents(buyResult, 'Buy protection');

    let poolBalanceAfter = await daiToken.balanceOf.call(unionDAIPool.address);
    let daiBalanceAfter = await daiToken.balanceOf.call(buyerAccount);

    assert.equal(daiBalanceBefore.sub(daiBalanceAfter).toString(), premium.toString(), 'Premium wasnt sent from buyers account');
    assert.equal(poolBalanceAfter.sub(poolBalanceBefore).toString(), premium.toString(), 'Premium has not arrived to pool account');
    assert.equal((await unionDAIPool.lockedPremium.call()).toString(), premium.toString(), 'Premium is not locked');

    console.log('Dai balance diff : ', daiBalanceBefore.sub(daiBalanceAfter).toString());

    let uUNNBalance = await uUNNTokenInstance.balanceOf(buyerAccount);
    let tokenID = await uUNNTokenInstance.tokenOfOwnerByIndex.call(buyerAccount, toBN(0));
    let address = await uUNNTokenInstance.protectionContract.call(tokenID);
    
    let scProtecionContract = await SCProtections.at(address);
    let protectionData = await scProtecionContract.getProtectionData(tokenID);


    console.log('  ID : ', tokenID.toString());
    console.log('  Pool address : ', protectionData[0].toString());
    console.log('  Protection type : ', protectionData[1].toString());
    console.log('  Protection amount : ', protectionData[2].toString());
    console.log('  Protection premium : ', protectionData[3].toString());
    console.log('  Protection issuedOn : ', protectionData[4].toString());
    console.log('  Protection validTo : ', protectionData[5].toString());
    });
    
it('should withdraw', async () =>{
        let withdrawAccount = accounts[4];
        let withdrawAccountBalanceBefore = await unionDAIPool.balanceOf(withdrawAccount);
        const privateKey = "e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178";
        let requestID = toBN(1);
        let amount = toBN(10).mul(decimals);
        // withdrawWithData(uint256 _requestID, uint256 _amount, uint256[5] memory _data, bytes memory _signature)
    //   @param _requestID - request ID generated on the backend (for reference)
    //   @param _amount - amount of liquidity to be withdrawn
    //   @param _data - data package with withdraw quotation. The package structure provided below: 
    //         _data[0] = requestID - request ID generated on the backend (for reference)
    // *       _data[1] = amount - amount of liquidity to be withdrawn
    // *       _data[2] = mcr - MCR value as of mcrBlockNumber
    // *       _data[3] = mcrBlockNumber - a block number MCR was calculated for
    // *       _data[4] = deadline - operation deadline, timestamp in seconds
    //   @param _signature - _data package signature that will be validated against whitelisted key.
        let mcr = toBN(1000).mul(decimals);
        let block = await web3.eth.getBlock("latest");
        let mcrBlockNumber = block.number;
        let deadline = Math.round((new Date().getTime() + (1 * 24 * 60 * 60 * 1000)) / 1000);
        let dataArr = [requestID, amount, mcr, mcrBlockNumber, deadline];

        let message = [
            {
                type: "uint256",
                value: requestID.toString()
            },
            {
                type: "uint256",
                value: amount.toString()
            },
            {
                type: "uint256",
                value: mcr.toString()
            },
            {
                type: "uint256",
                value: mcrBlockNumber.toString()
            },
            {
                type: "uint256",
                value: deadline.toString()
            }];
        const signature = await signMessage(message, privateKey);
        const publicKeySigner = EthCrypto.publicKeyByPrivateKey(privateKey);
        const signerAddress = EthCrypto.publicKey.toAddress(publicKeySigner);
        let allowed = await  unionDAIPool.hasRole(web3.utils.keccak256('MCR_PROVIDER'), signerAddress);
        assert.equal(allowed, true, 'signerAddress is not MCR_PROVIDER');
        let poolBalanceBefore = await daiToken.balanceOf(unionDAIPool.address);

        await expectRevert(
            unionDAIPool.withdrawWithData.sendTransaction(requestID, amount, dataArr, signature, {from: withdrawAccount}),
            'revert'
            );
        //update timelock
        await unionDAIPool.setLockupPeriod.sendTransaction(toBN(1), {from: adminAddress});
        await unionDAIPool.withdrawWithData.sendTransaction(requestID, amount, dataArr, signature, {from: withdrawAccount}),
        await unionDAIPool.setLockupPeriod.sendTransaction(toBN(7*24*3600), {from: adminAddress});

        let poolBalanceAfter = await daiToken.balanceOf(unionDAIPool.address);
        let withdrawAccountBalanceAfter = await unionDAIPool.balanceOf(withdrawAccount);
        // console.log('Balance before : ', withdrawAccountBalanceBefore.toString());
        // console.log('Balance after : ', withdrawAccountBalanceAfter.toString());

        // console.log('Pool balance before: ', poolBalanceBefore.toString());
        // console.log('Pool balance after: ', poolBalanceAfter.toString());
        
        // console.log('Balance Diff : ', withdrawAccountBalanceBefore.sub(withdrawAccountBalanceAfter).toString());
        assert.notEqual(withdrawAccountBalanceBefore.sub(withdrawAccountBalanceAfter), toBN(0));
        assert.notEqual(poolBalanceBefore.sub(poolBalanceAfter).toString(), toBN(0));
});

it('should fill claim, set claim status in review', async () =>{
    let duration = time.duration.days(3);

    await time.increase(duration);

    //from buyer of protection
    let buyerAccount = accounts[2];
    await buyDAI(uniswapUtil, buyerAccount);
    await approveToken(daiToken, buyerAccount, scpClaimsInstance.address);
    // let claimManager = signatureWallet;
    let poolAddress = await scProtectionSeller.getActiveSCProtectionPool(ppID);
    console.log('Pool address: ', poolAddress);
    timestamp = Math.round((new Date().getTime() + (3 * 24 * 60 * 60 * 1000)) / 1000);
    timestamp = timestamp - timestamp%86400;
    await scpClaimsInstance.fillClaim(ppID, timestamp, {from: buyerAccount});   
    await scpClaimsInstance.setClaimInReview(ppID, timestamp, {from: claimManager});
    let claimData = await scpClaimsInstance.getClaimData(ppID, timestamp);
    showClaimData(claimData);
    assert.equal(claimData[0].toString(), '2', 'Claims status is not \'In review\'');

});

it('should approve claim and exercise', async() =>{
    let buyerAccount = accounts[2];
    let payAmountPercentage = toBN(10); //10%
    //set claim approved
    await scpClaimsInstance.setClaimApproved.sendTransaction(ppID, timestamp, payAmountPercentage, {from: claimManager});
    let claimData = await scpClaimsInstance.getClaimData(ppID, timestamp);
    showClaimData(claimData);
    assert.equal(claimData[0].toString(), '3', 'Claim status is not Approved');

    let requestID = toBN(1);
    let clientBalanceBefore = await daiToken.balanceOf(buyerAccount);
    let poolStat = await unionDAIPool.getPoolStat.call();
    let totalCapBeforeEx = poolStat[0].toString();

    await scProtectionSeller.exercise.sendTransaction(requestID, timestamp, {from: buyerAccount});
    
    poolStat = await unionDAIPool.getPoolStat.call();
    let totalCapAfterEx = poolStat[0].toString();
    let poolCapDiff = toBN(totalCapBeforeEx).sub(toBN(totalCapAfterEx));
    
    let clientBalanceAfter = await daiToken.balanceOf(buyerAccount);
    let balanceDiff = toBN(clientBalanceAfter.toString()).sub(toBN(clientBalanceBefore.toString()));

    assert.notEqual(poolCapDiff, toBN(0));
    assert.notEqual(balanceDiff, toBN(0));
    await printPoolStat(unionDAIPool);
    
});

it('should revert exercise because of claim reject', async () =>{
    // let buyerAccount = accounts[2];
    let buyerAccount = accounts[3];
    let validTo = new Date().getTime() + (2 *24 * 60 * 60 * 1000);
    let premium = toBN(5).mul(decimals);
    // let tokenId = toBN(1);
    let tokenId = toBN(2);
    let amount = toBN(10).mul(decimals);
    let mcr = toBN(1000).mul(decimals);
    let mcrIncrement = toBN(200).mul(decimals);
    let poolAddress = unionDAIPool.address;
    let block = await web3.eth.getBlock("latest");
    let mcrBlockNumber = block.number;
    let deadline = Math.round((new Date().getTime() + ( 4 * 24 * 60 * 60 * 1000 )) / 1000);
    // console.log('poolAddress : ', poolAddress.toString());
    let dataArr = [tokenId, premium, validTo, amount, poolAddress, mcr, mcrBlockNumber, mcrIncrement, deadline];
    const privateKey = "e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178"; 
    //
    let message = [
      {
        type: "uint256",
        value: tokenId.toString(),
      },
      {
        type: "uint256",
        value: premium.toString(),
      },
      {
        type: "uint256",
        value: validTo.toString(),
      },
      {
        type: "uint256",
        value: amount.toString(),
      },
      {
        type: "uint256",
        value: poolAddress.toString(),
      },
      {
        type: "uint256",
        value: mcr.toString(),
      },
      {
        type: "uint256",
        value: mcrBlockNumber.toString(),
      },
      {
        type: "uint256",
        value: mcrIncrement.toString(),
      },
      {
        type: "uint256",
        value: deadline.toString(),
      },
    ];
    const signature = await signMessage(message, privateKey);
    const publicKeySigner = EthCrypto.publicKeyByPrivateKey(privateKey);
    const signerAddress = EthCrypto.publicKey.toAddress(publicKeySigner);
    let allowed = await scProtectionSeller.hasRole(web3.utils.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signerAddress);
    assert.equal(allowed, true, 'Signer account is not PROTECTION_PREMIUM_DATA_PROVIDER');

    await approveToken(daiToken, buyerAccount, scProtectionSeller.address);
    
    //buy protection
    let buyResult = await buyProtection(scProtectionSeller, dataArr, signature, deadline, buyerAccount);
    printEvents(buyResult, 'Buy protection');

    //shift time
    let duration = time.duration.days(1);

    await time.increase(duration);
    //fill claim
    let newTimestamp = timestamp+86400; // timestamp for new claim
    console.log('NewTimestamp: ', newTimestamp.toString());
    
    await approveToken(daiToken, buyerAccount, scpClaimsInstance.address);
    await scpClaimsInstance.fillClaim(ppID, newTimestamp, {from: buyerAccount});   

    //set claim in review
    await scpClaimsInstance.setClaimInReview(ppID, newTimestamp, {from: claimManager});

    //set claim rejected
    await scpClaimsInstance.setClaimRejected.sendTransaction(ppID, newTimestamp, {from: claimManager});
    let claimData = await scpClaimsInstance.getClaimData(ppID, newTimestamp);
    showClaimData(claimData);
    assert.equal(claimData[0].toString(), '4', 'Claim status is not Rejected');

    let requestID = tokenId;
    let clientBalanceBefore = await daiToken.balanceOf(buyerAccount);
    let poolStat = await unionDAIPool.getPoolStat.call();
    let totalCapBeforeEx = poolStat[0].toString();

    await expectRevert(
        scProtectionSeller.exercise.sendTransaction(requestID, newTimestamp, {from: buyerAccount}),
        'revert'
    ) //reverted due to claim reject
    
    poolStat = await unionDAIPool.getPoolStat.call();
    let totalCapAfterEx = poolStat[0].toString();
    let poolCapDiff = toBN(totalCapBeforeEx).sub(toBN(totalCapAfterEx));
    
    let clientBalanceAfter = await daiToken.balanceOf(buyerAccount);
    let balanceDiff = toBN(clientBalanceAfter.toString()).sub(toBN(clientBalanceBefore.toString()));

    // console.log('cap diff: ', poolCapDiff.toString());
    // console.log('balance Diff: ', balanceDiff.toString());
    assert.equal(poolCapDiff.toString(), toBN(0).toString());
    assert.equal(balanceDiff.toString(), toBN(0).toString());
});
it('should unlock premium', async () =>{
    await printPoolStat(unionDAIPool);
    let poolReserveBalanceBeforeUnlock = await unionDAIPool.poolReserveBalance.call();
    let foundationReserveBalanceBeforeUnlock = await unionDAIPool.foundationReserveBalance.call();
    
    console.log('pool reserve balance before unlock: ', poolReserveBalanceBeforeUnlock.toString());
    console.log('foundation balance before unlock: ', foundationReserveBalanceBeforeUnlock.toString());
    
    let buyerAccount = accounts[3];
    let validTo = Math.round((new Date().getTime() + ( 10 * 24 * 60 * 60 * 1000 )) / 1000);
    let premium = toBN(5).mul(decimals);
    let tokenId = toBN(3);
    let amount = toBN(10).mul(decimals);
    let mcr = toBN(1000).mul(decimals);
    let mcrIncrement = toBN(200).mul(decimals);
    // let poolAddress = unionDAIPool.address;
    let poolAddress = unionDAIPool.address;
    let block = await web3.eth.getBlock("latest");
    let mcrBlockNumber = block.number;
    let deadline = Math.round((new Date().getTime() + ( 5 * 24 * 60 * 60 * 1000 )) / 1000);
    // console.log('poolAddress : ', poolAddress.toString());
    let dataArr = [tokenId, premium, validTo, amount, poolAddress, mcr, mcrBlockNumber, mcrIncrement, deadline];
    const privateKey = "e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178"; 
    //
    let message = [
      {
        type: "uint256",
        value: tokenId.toString(),
      },
      {
        type: "uint256",
        value: premium.toString(),
      },
      {
        type: "uint256",
        value: validTo.toString(),
      },
      {
        type: "uint256",
        value: amount.toString(),
      },
      {
        type: "uint256",
        value: poolAddress.toString(),
      },
      {
        type: "uint256",
        value: mcr.toString(),
      },
      {
        type: "uint256",
        value: mcrBlockNumber.toString(),
      },
      {
        type: "uint256",
        value: mcrIncrement.toString(),
      },
      {
        type: "uint256",
        value: deadline.toString(),
      },
    ];
    const signature = await signMessage(message, privateKey);
    const publicKeySigner = EthCrypto.publicKeyByPrivateKey(privateKey);
    const signerAddress = EthCrypto.publicKey.toAddress(publicKeySigner);
    let allowed = await scProtectionSeller.hasRole(web3.utils.keccak256('PROTECTION_PREMIUM_DATA_PROVIDER'), signerAddress);
    assert.equal(allowed, true, 'Signer account is not PROTECTION_PREMIUM_DATA_PROVIDER');

    let daiBalanceBefore = await daiToken.balanceOf.call(buyerAccount);
    let poolBalanceBefore = await daiToken.balanceOf.call(unionDAIPool.address);
    // console.log('daiBalanceBefore: ', daiBalanceBefore.toString());
    await approveToken(daiToken, buyerAccount, scProtectionSeller.address);
    
    //buy protection
    let lockedPremiumBefore = await unionDAIPool.lockedPremium.call();
    let buyResult = await buyProtection(scProtectionSeller, dataArr, signature, deadline, buyerAccount);
    // printEvents(buyResult, 'Buy protection');
    
    let uunnBalance = await uUNNTokenInstance.balanceOf(buyerAccount);
    console.log('UUNN buyer account balance: ', uunnBalance.toString());

    let poolBalanceAfter = await daiToken.balanceOf.call(unionDAIPool.address);
    let daiBalanceAfter = await daiToken.balanceOf.call(buyerAccount);

    assert.equal(daiBalanceBefore.sub(daiBalanceAfter).toString(), premium.toString(), 'Premium wasnt sent from buyers account');
    assert.equal(poolBalanceAfter.sub(poolBalanceBefore).toString(), premium.toString(), 'Premium has not arrived to pool account');
    let lockedPremiumAfter = await unionDAIPool.lockedPremium.call();
    assert.equal(toBN(lockedPremiumAfter.toString()).sub(toBN(lockedPremiumBefore.toString())).toString(), premium.toString(), 'Premium is not locked');
    
    // console.log('Dai balance diff : ', daiBalanceBefore.sub(daiBalanceAfter).toString());

    await time.increase(time.duration.days(10));

    let protectionData = await scProtectionSeller.getProtectionData(tokenId);
    showProtectionData(protectionData);
    console.log('Now: ', (await time.latest()).toString());

    let res = await unionDAIPool.unlockPremium.sendTransaction([tokenId], {
      from: buyerAccount
  });
  printEvents(res, "Unlock events");
    
    let lockedPremiumAfterUnlock = await unionDAIPool.lockedPremium.call();
    console.log('Locked premium after unlock: ', lockedPremiumAfterUnlock.toString());

    const poolReserveBalanceAfterUnlock = await unionDAIPool.poolReserveBalance.call();
    const foundationReserveBalanceAfterUnlock = await unionDAIPool.foundationReserveBalance.call();

    console.log('pool reserve after unlock: ', poolReserveBalanceAfterUnlock.toString());
    console.log('foundation reserve after unlock: ', foundationReserveBalanceAfterUnlock.toString());

    const poolReservePremiumPercentDenom = await unionDAIPool.poolReservePremiumPercentDenom.call();
    const poolReservePremiumPercentNom = await unionDAIPool.poolReservePremiumPercentNom.call();
    const foundationReservePremiumPercentNom = await unionDAIPool.foundationReservePremiumPercentNom.call();
    const foundationReservePremiumPercentDenom = await unionDAIPool.foundationReservePremiumPercentDenom.call();

    const totalPremiumMatured = premium;
    const poolReserveCommission = totalPremiumMatured * poolReservePremiumPercentNom / poolReservePremiumPercentDenom;
    console.log('Pool reserve commission',poolReserveCommission);
    
    const correctPoolReserve = Number(poolReserveCommission) + Number(poolReserveBalanceBeforeUnlock);
    const foundationReserveCommission = totalPremiumMatured * foundationReservePremiumPercentNom / foundationReservePremiumPercentDenom;
    const correctFoundationReserver = Number(foundationReserveCommission) + Number(foundationReserveBalanceBeforeUnlock);
    console.log('Correct pool reserve', correctPoolReserve);
    console.log('Pool reserve balance after unlock',poolReserveBalanceAfterUnlock.toString());
    assert.equal(poolReserveBalanceAfterUnlock.toString(), correctPoolReserve.toString(), 'Invalid pool reserve balance');
    assert.equal(foundationReserveBalanceAfterUnlock.toString(), correctFoundationReserver.toString(), 'Invalid foundation reserve balance');
    
});


it('should appeal claim and exercise protection', async () => {
    console.log("******************************************");
    let buyerAccount = accounts[3];
    // set claim appeal
    let newTimestamp = timestamp+86400; // timestamp from previous test case
    await buyDAI(uniswapUtil, buyerAccount);
    await approveToken(daiToken, buyerAccount, scpClaimsInstance.address);
    await scpClaimsInstance.setChallengePeriod.sendTransaction(toBN(5*86400*1000), {from: accounts[0]});

    let claimData2 = await scpClaimsInstance.getClaimData(ppID, newTimestamp);
    showClaimData(claimData2);
    console.log("challengePeriod",(await scpClaimsInstance.challengePeriod.call()).toString());

    await scpClaimsInstance.setClaimAppeal(ppID, newTimestamp, {from: buyerAccount});
    let claimData = await scpClaimsInstance.getClaimData(ppID, newTimestamp);
    assert.equal(claimData[0].toString(), '5', 'Claim is not appealed');

    //set claim approved
    let payAmountPercentage = 10; //10 %
    await scpClaimsInstance.setClaimApproved(ppID, newTimestamp, payAmountPercentage, {from: claimManager});
    claimData = await scpClaimsInstance.getClaimData(ppID, newTimestamp);
    assert.equal(claimData[0].toString(), '3', 'Claim is not approved');
    //exercise
    let requestID = toBN(2);
    let clientBalanceBefore = await daiToken.balanceOf(buyerAccount);
    let poolStat = await unionDAIPool.getPoolStat();
    let totalCapBeforeEx = await poolStat[0].toString();
    
    await scProtectionSeller.exercise.sendTransaction(requestID, newTimestamp, {from: buyerAccount});

    poolStat = await unionDAIPool.getPoolStat();
    let totalCapAfterEx = poolStat[0].toString();
    let poolCapDiff = toBN(totalCapBeforeEx).sub(toBN(totalCapAfterEx));
    let clientBalanceAfter = await daiToken.balanceOf(buyerAccount);
    let balanceDiff = toBN(clientBalanceAfter.toString()).sub(toBN(clientBalanceBefore.toString()));
    
    assert.notEqual(poolCapDiff, toBN(0));
    assert.notEqual(balanceDiff, toBN(0));


});

it('should revert withdraw: Invalid signature', async () => {
    let withdrawAccount = accounts[4];
    let requestID = toBN(1);
    let amount = toBN(2).mul(decimals); 
    let mcr = toBN(1000).mul(toBN(decimals));
    let block = await web3.eth.getBlock("latest");
    let mcrBlockNumber = block.number;
    let deadline = Math.round((new Date().getTime() + (5 * 24 * 60 * 60 * 1000)) / 1000);
    let dataArr = [requestID, amount, mcr, mcrBlockNumber, deadline];
    const privateKey = "e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979dd0832a5178"; // invalid private key
    let message = [
      {
        type: "uint256",
        value: requestID.toString(),
      },
      {
        type: "uint256",
        value: amount.toString(),
      },
      {
        type: "uint256",
        value: mcr.toString(),
      },
      {
        type: "uint256",
        value: mcrBlockNumber.toString(),
      },
      {
        type: "uint256",
        value: deadline.toString(),
      },
    ];  

    const signature = await signMessage(message, privateKey);
    const publicKeySigner = EthCrypto.publicKeyByPrivateKey(privateKey);
    const signerAddress = EthCrypto.publicKey.toAddress(publicKeySigner);
    let allowed = await unionDAIPool.hasRole(web3.utils.keccak256("MCR_PROVIDER"), signerAddress);
    console.log('Allow  status: ', allowed );
    await approveToken(unionDAIPool, withdrawAccount, unionDAIPool.address);
    await expectRevert.unspecified(
        unionDAIPool.withdrawWithData.sendTransaction(requestID, amount, dataArr, signature, {
            from: withdrawAccount
        })
    );
});



});