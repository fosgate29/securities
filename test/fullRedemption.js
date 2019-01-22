const Promise = require("bluebird");
const { shouldFail } = require("openzeppelin-test-helpers");
// const latestTime = require("./helpers/latestTime");
// import increaseTime, { duration } from "./helpers/increaseTime";

web3.eth = Promise.promisifyAll(web3.eth);

const FullRedemption = artifacts.require("FullRedemption");
const PaymentToken = artifacts.require("PaymentTokenMock");
const RedeemableToken = artifacts.require("RedeemableTokenMock");

contract("FullRedemption", accounts => {
  let fullRedemption;
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

    fullRedemption = await FullRedemption.new(
        paymentToken.address,
        securityToken.address,
        paymentOwner,
        5,
        { from: issuer }
    );
  });

  it("should be owned by the issuer", async () => {
    const currentOwner = await fullRedemption.owner.call();
    assert.strictEqual(currentOwner, issuer, "Contract is not owned by issuer");
  });

  it("should fail to setup without access to any payment tokens", async () => {
    await shouldFail.reverting(fullRedemption.setup({ from: issuer }));
  });

  it("should fail to setup without access to enough payment tokens", async () => {
    await paymentToken.approve(fullRedemption.address, 4999, { from : paymentOwner });
    await shouldFail.reverting(fullRedemption.setup({ from: issuer }));
  });

  it("should succeed to setup with access to enough payment tokens", async () => {
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    const setupBool = await fullRedemption.isSetUp.call();
    assert.isTrue(setupBool, "Setup was not successful");
  });

  it("should succeed not be possible to redeem tokens without having setup", async () => {
    await shouldFail.reverting(fullRedemption.redeemTokens([holderOne, holderTwo], { from: issuer }));
  });

  it("should not redeem tokens without setting the redemption contract address in the token ", async () => {
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });

    await shouldFail.reverting(fullRedemption.redeemTokens([holderOne, holderTwo], { from: issuer }));
  });

  it("should set the redemption contract in the token", async () => {
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});
  });

  it("should redeem tokens for a token holder", async () => {
    // setup and set redemption address
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});

    // check prior security token and payment token balances
    let securityBalance = await securityToken.balanceOf.call(holderOne);
    assert.isTrue(securityBalance.eq(new web3.utils.BN(100)));

    const priorPaymentBalance = await paymentToken.balanceOf.call(holderOne);

    // carry out redemption
    await fullRedemption.redeemTokens([holderOne], { from: issuer });

    // check new balances
    securityBalance = await securityToken.balanceOf.call(holderOne);
    assert.isTrue(securityBalance.eq(new web3.utils.BN(0)));

    const postPaymentBalance = await paymentToken.balanceOf.call(holderOne);
    assert.isTrue(postPaymentBalance.sub(priorPaymentBalance).eq(new web3.utils.BN(5*100)));
  });

  it("should redeem tokens for an array of token holders", async () => {
    // setup and set redemption address
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});

    // carry out redemption
    await fullRedemption.redeemTokens([holderOne, holderTwo, holderThree], { from: issuer });

    // check new security balances
    const securityBalanceOne = await securityToken.balanceOf.call(holderOne);
    const securityBalanceTwo = await securityToken.balanceOf.call(holderTwo);
    const securityBalanceThree = await securityToken.balanceOf.call(holderThree);
    assert.isTrue(securityBalanceOne.eq(new web3.utils.BN(0)));
    assert.isTrue(securityBalanceTwo.eq(new web3.utils.BN(0)));
    assert.isTrue(securityBalanceThree.eq(new web3.utils.BN(0)));

    // check new payment balances
    const paymentBalanceOne = await paymentToken.balanceOf.call(holderOne);
    const paymentBalanceTwo = await paymentToken.balanceOf.call(holderTwo);
    const paymentBalanceThree = await paymentToken.balanceOf.call(holderThree);
    assert.isTrue(paymentBalanceOne.eq(new web3.utils.BN(5*100)));
    assert.isTrue(paymentBalanceTwo.eq(new web3.utils.BN(5*200)));
    assert.isTrue(paymentBalanceThree.eq(new web3.utils.BN(5*300)));
  });

  it("should not redeem tokens for the same holder twice", async () => {
    // setup and set redemption address
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});

    // carry out redemption
    await fullRedemption.redeemTokens([holderOne, holderTwo, holderThree], { from: issuer });

    // try to redeem holderOne's tokens again
    await shouldFail.reverting(fullRedemption.redeemTokens([holderOne], { from: issuer }));
  });

  it("should allow token redemptions in multiple transactions", async () => {
    // setup and set redemption address
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});

    // carry out redemption
    await fullRedemption.redeemTokens([holderOne, holderTwo], { from: issuer });
    await fullRedemption.redeemTokens([holderThree], { from: issuer });
    await fullRedemption.redeemTokens([holderFour], { from: issuer });
  });

  it("should not allow token redemptions if someone has no securities", async () => {
    // setup and set redemption address
    await paymentToken.approve(fullRedemption.address, 5000, { from : paymentOwner });
    await fullRedemption.setup({ from: issuer });
    await securityToken.setRedemption(fullRedemption.address, { from: tokenOwner});

    // try to carry out redemption
    await shouldFail.reverting(fullRedemption.redeemTokens([notHolder], { from: issuer }));
  });

});
