const Promise = require("bluebird");
const { shouldFail, time } = require("openzeppelin-test-helpers");

web3.eth = Promise.promisifyAll(web3.eth);

const FixedPriceTender = artifacts.require("FixedPriceTender");
const PaymentToken = artifacts.require("PaymentTokenMock");
const RedeemableToken = artifacts.require("RedeemableTokenMock");

contract("FixedPriceTender", accounts => {
  let fixedPriceTender;
  let securityToken;
  let paymentToken;

  const issuer = accounts[0];
  const tokenOwner = accounts[1];
  const holderOne = accounts[2];
  const holderTwo = accounts[3];
  const holderThree = accounts[4];
  const holderFour = accounts[5];
  const notHolder = accounts[6];

  beforeEach(async () => {
    securityToken = await RedeemableToken.new(issuer, 1000, { from: tokenOwner });
    paymentToken = await PaymentToken.new(issuer, 1000000, { from: issuer });

    await securityToken.transfer(holderOne, 100, { from: issuer });
    await securityToken.transfer(holderTwo, 200, { from: issuer });
    await securityToken.transfer(holderThree, 300, { from: issuer });
    await securityToken.transfer(holderFour, 400, { from: issuer });

    let endTime = (await time.latest()) + time.duration.weeks(1);

    fixedPriceTender = await FixedPriceTender.new(
        5,
        paymentToken.address,
        securityToken.address,
        issuer,
        400,
        endTime,
        { from: issuer }
    );
  });

  it("should be owned by the issuer", async () => {
    const currentOwner = await fixedPriceTender.owner.call();
    assert.strictEqual(currentOwner, issuer, "Contract is not owned by issuer");
  });

  it("should fail to setup without access to any payment tokens", async () => {
    await shouldFail.reverting(fixedPriceTender.setup({ from: issuer }));
  });

  it("should fail to setup without access to enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 1999, { from : issuer });
    await shouldFail.reverting(fixedPriceTender.setup({ from: issuer }));
  });

  it("should succeed to setup with access to enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.setup({ from: issuer });
    const setupBool = await fixedPriceTender.isSetUp.call();
    assert.isTrue(setupBool, "Setup was not successful");
  });

  it("should not allow the setup to be called again after succeeding", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.setup({ from: issuer });
    await shouldFail.reverting(fixedPriceTender.setup({ from: issuer }));   
  });

});
