const Promise = require("bluebird");
var CryptoJS = require("crypto-js");
const { shouldFail, time } = require("openzeppelin-test-helpers");

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
    const invalidHolder = accounts[4];
    
    beforeEach(async () => {
        securityToken = await SecurityToken.new(issuer, 1000000, { from: issuer });
        securityToken.transfer(holderOne, 1000, {from: issuer});
        securityToken.transfer(holderTwo, 500, {from: issuer});
        securityToken.transfer(holderThree, 1500, {from: issuer});
        let date = new Date();
        date.setDate(date.getDate() + 14)
        let endTime = Math.floor(date / 1000);
        onChainVoting = await OnChainVoting.new(securityToken.address, issuer, endTime, {from: issuer});
    });

    it("should be owned by owner", async () => {
        const currentOwner = await onChainVoting.owner.call();
        assert.strictEqual(currentOwner, issuer, "Contract is not owned by owner");
    });

    it("should hold 1000 tokens for HolderOne", async () => {
        const balance = await securityToken.balanceOf.call(holderOne);
        assert.isTrue(balance.eq(new web3.utils.BN(1000)), "Contract is not owned by owner");
    });

    it("should allow HolderOne to place their vote", async () => {
        var ciphertext = CryptoJS.AES.encrypt('0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3');
        await onChainVoting.placeVote(ciphertext.toString(), { from: holderOne });
        const voteCount = await onChainVoting.submissionsCount.call();
        assert.isTrue(voteCount.eq(new web3.utils.BN(1)), "Vote was not succesfully placed");
    })

    it("should store HolderTwo's vote correctely", async () => {
        var ciphertext = CryptoJS.AES.encrypt('7,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3');
        await onChainVoting.placeVote(ciphertext.toString(), { from: holderTwo });
        const voteSubmission = await onChainVoting.submissions.call(holderTwo);
        assert.strictEqual(voteSubmission, ciphertext.toString(), "Vote was not succesfully placed");
    })

    it("should not allow invalidHolder to vote", async () => {
        var ciphertext = CryptoJS.AES.encrypt('1,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3');
        await shouldFail.reverting(onChainVoting.placeVote(ciphertext.toString(), { from: invalidHolder }));
    })

    it("should not allow someone to vote after the specified time", async () => {
        var ciphertext = CryptoJS.AES.encrypt('1,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3');
        await time.increase(time.duration.years(3));
        await shouldFail.reverting(onChainVoting.placeVote(ciphertext.toString(), { from: holderThree }))
    })

});