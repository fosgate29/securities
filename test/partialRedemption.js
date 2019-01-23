const Promise = require("bluebird");
const { shouldFail } = require("openzeppelin-test-helpers");

web3.eth = Promise.promisifyAll(web3.eth);

const PartialRedemption = artifacts.require("PartialRedemption");
const PaymentToken = artifacts.require("PaymentTokenMock");
const RedeemableToken = artifacts.require("RedeemableTokenMock");

contract("PartialRedemption", accounts => {
  let partialRedemption;
  let securityToken;
  let paymentToken;

  const issuer = accounts[0];
  const tokenOwner = accounts[1];
  const paymentOwner = accounts[2];
  const holderOne = accounts[3];
  const holderTwo = accounts[4];
  const holderThree = accounts[5];
  const holderFour = accounts[6];
  const notHolder = accounts[7];

  beforeEach(async () => {
    securityToken = await RedeemableToken.new(issuer, 1000, { from: tokenOwner });
    paymentToken = await PaymentToken.new(paymentOwner, 1000000, { from: paymentOwner });

    await securityToken.transfer(holderOne, 100, { from: issuer });
    await securityToken.transfer(holderTwo, 200, { from: issuer });
    await securityToken.transfer(holderThree, 300, { from: issuer });
    await securityToken.transfer(holderFour, 400, { from: issuer });

    partialRedemption = await PartialRedemption.new(
        paymentToken.address,
        securityToken.address,
        paymentOwner,
        10,
        { from: issuer }
    );
  });

  it("should be owned by the issuer", async () => {
    const currentOwner = await partialRedemption.owner.call();
    assert.strictEqual(currentOwner, issuer, "Contract is not owned by issuer");
  });

  it("should not redeem tokens without setting the redemption contract address in the token ", async () => {
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });

    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne, holderTwo], [50, 100], { from: issuer }));
  });

  it("should set the redemption contract in the token", async () => {
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});
  });

  it("should fail if no token holders and numbers are passed", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // pass in no addresses
    await shouldFail.reverting(partialRedemption.redeemTokens([], [], { from: issuer }));
  });

  it("should fail if arrays of different lengths are passed", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // pass in different lengths of arrays
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne, holderFour], [50, 50, 50], { from: issuer }));
  });

  it("should redeem tokens for a token holder", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // check prior security token and payment token balances
    let securityBalance = await securityToken.balanceOf.call(holderFour);
    assert.isTrue(securityBalance.eq(new web3.utils.BN(400)));

    const priorPaymentBalance = await paymentToken.balanceOf.call(holderFour);

    // carry out redemption
    await partialRedemption.redeemTokens([holderFour], [257], { from: issuer });

    // check new balances
    securityBalance = await securityToken.balanceOf.call(holderFour);
    assert.isTrue(securityBalance.eq(new web3.utils.BN(143)));

    const postPaymentBalance = await paymentToken.balanceOf.call(holderFour);
    assert.isTrue(postPaymentBalance.sub(priorPaymentBalance).eq(new web3.utils.BN(10*257)));
  });

  it("should redeem tokens for an array of token holders", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // carry out redemption
    await partialRedemption.redeemTokens([holderOne, holderTwo, holderThree], [100, 150, 1], { from: issuer });

    // check new security balances
    const securityBalanceOne = await securityToken.balanceOf.call(holderOne);
    const securityBalanceTwo = await securityToken.balanceOf.call(holderTwo);
    const securityBalanceThree = await securityToken.balanceOf.call(holderThree);
    assert.isTrue(securityBalanceOne.eq(new web3.utils.BN(0)));
    assert.isTrue(securityBalanceTwo.eq(new web3.utils.BN(50)));
    assert.isTrue(securityBalanceThree.eq(new web3.utils.BN(299)));

    // check new payment balances
    const paymentBalanceOne = await paymentToken.balanceOf.call(holderOne);
    const paymentBalanceTwo = await paymentToken.balanceOf.call(holderTwo);
    const paymentBalanceThree = await paymentToken.balanceOf.call(holderThree);
    assert.isTrue(paymentBalanceOne.eq(new web3.utils.BN(10*100)));
    assert.isTrue(paymentBalanceTwo.eq(new web3.utils.BN(10*150)));
    assert.isTrue(paymentBalanceThree.eq(new web3.utils.BN(10*1)));
  });

  it("should not redeem tokens for the same holder twice if it goes over their total", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // carry out redemption
    await partialRedemption.redeemTokens([holderOne, holderTwo, holderFour], [99, 87, 300], { from: issuer });

    // try to redeem holderOne's tokens again
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne], [99], { from: issuer }));
  });

  it("should redeem tokens for the same holder twice if it does not go over their total", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // carry out redemption
    await partialRedemption.redeemTokens([holderOne, holderTwo, holderFour], [50, 87, 30], { from: issuer });

    const securityBalanceOne = await securityToken.balanceOf.call(holderOne);
    assert.isTrue(securityBalanceOne.eq(new web3.utils.BN(50)));

    // try to redeem holderOne's tokens again
    await partialRedemption.redeemTokens([holderOne, holderTwo], [49, 50], { from: issuer });

    const paymentBalanceOne = await paymentToken.balanceOf.call(holderOne);
    const paymentBalanceTwo = await paymentToken.balanceOf.call(holderTwo);
    assert.isTrue(paymentBalanceOne.eq(new web3.utils.BN(10*99)));
    assert.isTrue(paymentBalanceTwo.eq(new web3.utils.BN(10*137)));
  });

  it("should not allow token redemptions that go over the holder's total balance", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // carry out redemption
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne, holderTwo], [50, 201], { from: issuer }));
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne], [101], { from: issuer }));
  });

  it("should not allow redemptions when not enough payment tokens are available", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 100, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // carry out redemption - passes with enough payment tokens
    await partialRedemption.redeemTokens([holderOne, holderTwo], [5, 5], { from: issuer });

    // fails now that there arent enough payment tokens
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne], [1], { from: issuer }));
  });

  it("should not allow token redemptions if someone has no securities", async () => {
    // set redemption address
    await paymentToken.approve(partialRedemption.address, 5000, { from : paymentOwner });
    await securityToken.setRedemption(partialRedemption.address, { from: tokenOwner});

    // try to carry out redemption
    await shouldFail.reverting(partialRedemption.redeemTokens([holderOne, notHolder], [5, 1], { from: issuer }));
  });

});
