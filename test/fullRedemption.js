const Promise = require("bluebird");
const { shouldFail } = require("openzeppelin-test-helpers");
// const latestTime = require("./helpers/latestTime");
// import increaseTime, { duration } from "./helpers/increaseTime";
// const expectThrow = require("./helpers/expectThrow");

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

});
