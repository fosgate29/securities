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
        
        let blockchainTime = await time.latest();
        endTime = parseInt(blockchainTime) + parseInt(time.duration.weeks(1));
        
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
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        const voteCount = await onChainVoting.submissionsCount.call();
        assert.isTrue(voteCount.eq(new web3.utils.BN(1)), "Vote was not succesfully placed");
    });

    it("should store HolderTwo's vote correctely", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt7654&7,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderTwo });
        const voteSubmission = await onChainVoting.submissions.call(holderTwo);
        assert.strictEqual(voteSubmission, ciphertext, "Vote was not succesfully placed");
    });

    it("should not allow invalidHolder to vote", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt9876&1,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await shouldFail.reverting(onChainVoting.placeVote(ciphertext, { from: invalidHolder }));
    });

    it("should not allow someone to vote after the specified time", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt3765&1,0,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await time.increase(time.duration.weeks(2));
        await shouldFail.reverting(onChainVoting.placeVote(ciphertext, { from: holderThree }));
    });

    it("should not allow a voter to vote a second time", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await shouldFail.reverting(onChainVoting.placeVote(ciphertext, { from: holderOne }));
    });

    it("should allow the issuer to submit a users vote", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await time.increase(time.duration.weeks(2));
        const holderOneVote = await onChainVoting.submissions.call(holderOne);
        let decryptedVote = CryptoJS.AES.decrypt(holderOneVote, 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3');
        decryptedVote = decryptedVote.toString(CryptoJS.enc.Utf8);
        const index = decryptedVote.lastIndexOf('&');
        const salt = decryptedVote.substring(0, index);
        const vote = decryptedVote.substring(index+1);
        const convertedVote = web3.utils.utf8ToHex(vote)
        const hashedSalt = web3.utils.sha3(salt);
        await onChainVoting.submitUserVotes([hashedSalt],[convertedVote], {from: issuer});
        const submittedVote = await onChainVoting.votes.call(hashedSalt);
        assert.strictEqual(web3.utils.hexToUtf8(submittedVote), vote, "submitted vote does not equal users vote");
    });

    it("should not allow the issuer to count votes before the vote has ended", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne })
        await shouldFail.reverting(onChainVoting.submitUserVotes([web3.utils.sha3('salt1234')],[web3.utils.utf8ToHex('0,4,0')], {from: issuer}));
    });

    it("should not allow anyone but the issuer to submit users votes", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await time.increase(time.duration.weeks(2));
        await shouldFail.reverting(onChainVoting.submitUserVotes([web3.utils.sha3('fakesalt')],[web3.utils.utf8ToHex('0,10,0')], {from: holderOne}));
    })

    it("should not allow issuer to submit a vote that has already been submitted", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        const ciphertext2 = CryptoJS.AES.encrypt('salt4567&0,6,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await onChainVoting.placeVote(ciphertext2, { from: holderTwo });
        await time.increase(time.duration.weeks(2));
        await shouldFail.reverting(onChainVoting.submitUserVotes([web3.utils.sha3('salt1234'), web3.utils.sha3('salt1234')],[web3.utils.utf8ToHex('0,4,0'), web3.utils.utf8ToHex('0,4,0')], {from: issuer}));
    })

    it("should not allow issuer to submit a different number of votes to salts", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        const ciphertext2 = CryptoJS.AES.encrypt('salt4567&0,6,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await onChainVoting.placeVote(ciphertext2, { from: holderTwo });
        await time.increase(time.duration.weeks(2));
        await shouldFail.reverting(onChainVoting.submitUserVotes([web3.utils.sha3('salt1234'), web3.utils.sha3('salt4567')],[web3.utils.utf8ToHex('0,4,0')], {from: issuer}));
    })

    it("should not allow issuer to finalize the vote with invalid number of votes submitted", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await onChainVoting.placeVote(ciphertext, { from: holderTwo });
        await time.increase(time.duration.weeks(2));
        await onChainVoting.submitUserVotes([web3.utils.sha3('salt1234')],[web3.utils.utf8ToHex('0,4,0')], {from: issuer});
        await shouldFail.reverting(onChainVoting.finalizeVote('0,4,0', {from: issuer}))
    })

    it("should not allow issuer to finalize the vote twice", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        const ciphertext2 = CryptoJS.AES.encrypt('salt4567&0,6,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await onChainVoting.placeVote(ciphertext2, { from: holderTwo });
        await time.increase(time.duration.weeks(2));
        await onChainVoting.submitUserVotes([web3.utils.sha3('salt1234'), web3.utils.sha3('salt4567')],[web3.utils.utf8ToHex('0,4,0'), web3.utils.utf8ToHex('0,6,0')], {from: issuer});
        await onChainVoting.finalizeVote('0,10,0', {from: issuer})
        await shouldFail.reverting(onChainVoting.finalizeVote('0,15,0', {from: issuer}))
    })

    it("should not allow issuer to finalize the vote before it has ended", async () => {
        const ciphertext = CryptoJS.AES.encrypt('salt1234&0,4,0', 'c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3').toString();;
        await onChainVoting.placeVote(ciphertext, { from: holderOne });
        await shouldFail.reverting(onChainVoting.finalizeVote('0,10,0', {from: issuer}))
    })


});