const Promise = require("bluebird");
// const increaseTime = require("./node_modules/openzeppelin-solidity/helpers/increaseTime");
// const { BN, constants, expectEvent, shouldFail } = require('openzeppelin-test-helpers');

web3.eth = Promise.promisifyAll(web3.eth);

const OnChainVoting = artifacts.require("OnChainVoting");
const SecurityToken = artifacts.require("RedeemableTokenMock")

contract("OnChainVoting", accounts => {
    let onChainVoting;
    let securityToken;

    const issuer = accounts[0];
    const holderOne = accounts[1];
    const holderTwo = accounts[2];
    const holderThree = accounts[3];
    let date = (new Date("03/17/2020")).getTime();
    let unixDate = Math.floor(date / 1000);
    
    
    beforeEach(async () => {
        securityToken = await SecurityToken.new(issuer, 1000000, { from: issuer });
        securityToken.transfer(holderOne, 1000, {from: issuer});
        securityToken.transfer(holderTwo, 500, {from: issuer});
        securityToken.transfer(holderThree, 1200, {from: issuer});
        onChainVoting = await OnChainVoting.new(securityToken.address, issuer, unixDate, {from: issuer});
    })

    it("should be owned by owner", async () => {
        const currentOwner = await onChainVoting.owner.call();
        assert.strictEqual(currentOwner, issuer, "Contract is not owned by owner");
    });

    it("HolderOne should have 1000 tokens", async () => {
        const balance = await securityToken.balanceOf.call(holderOne);
        const tokenBalance = new web3.utils.BN(1000)
        assert.isTrue(tokenBalance.eq(balance), "Contract is not owned by owner");
    })

});
