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
    await shouldFail.reverting(fixedPriceTender.paymentTokensReady({ from: issuer }));
  });

  it("should fail to setup without access to enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 1999, { from : issuer });
    await shouldFail.reverting(fixedPriceTender.paymentTokensReady({ from: issuer }));
  });

  it("should succeed to setup with access to enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });
    const setupBool = await fixedPriceTender.paymentReady.call();
    assert.isTrue(setupBool, "Setup was not successful");
  });

  it("should not allow the setup to be called again after succeeding", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });
    await shouldFail.reverting(fixedPriceTender.paymentTokensReady({ from: issuer }));   
  });

  it("should allow the end time to be updated", async () => {
    let endTime = await fixedPriceTender.offerEndTime.call();
    const newEndTime = parseInt(endTime) + parseInt(time.duration.weeks(3));
    await fixedPriceTender.updateOfferEndTime(newEndTime, { from: issuer });
    endTime = await fixedPriceTender.offerEndTime.call();
    assert.strictEqual(newEndTime, parseInt(endTime), "New end time has not updated correctly");
  });

  it("should not allow a new end time in the past", async () => {
    const newEndTime = parseInt(await time.latest()) - parseInt(time.duration.hours(1));
    await shouldFail.reverting(fixedPriceTender.updateOfferEndTime(newEndTime, { from: issuer }));
  });

  it("should allow the tokens to repurchase to be updated", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await fixedPriceTender.updateTotalToRepurchase(300, { from: issuer });
    const newTotalToRepurchase = await fixedPriceTender.totalToRepurchase.call();
    assert.strictEqual(parseInt(newTotalToRepurchase), 300, "New number to repurchase has not updated correctly");
  });

  it("should not allow the tokens to repurchase to be updated if contract doesnt have enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await shouldFail.reverting(fixedPriceTender.updateTotalToRepurchase(401, { from: issuer }));
  });

  it("should not allow a negative total to repurchase", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await shouldFail.reverting(fixedPriceTender.updateTotalToRepurchase(-1, { from: issuer }));
  });

  it("should not allow a new total to repurchase larger than the token supply", async () => {
    await paymentToken.approve(fixedPriceTender.address, 5005, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await shouldFail.reverting(fixedPriceTender.updateTotalToRepurchase(1001, { from: issuer }));
  });

  it("should allow the payment per security to be updated", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await fixedPriceTender.updatePaymentPerSecurity(4, { from: issuer });
    const newPayment = await fixedPriceTender.paymentPerSecurity.call();
    assert.strictEqual(parseInt(newPayment), 4, "New payment per security not updated");
  });

  it("should not allow the payment per security to be updated if contract doesnt have enough payment tokens", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await shouldFail.reverting(fixedPriceTender.updatePaymentPerSecurity(6, { from: issuer }));
  });

  it("should not allow a negative or 0 payment per security", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await shouldFail.reverting(fixedPriceTender.updatePaymentPerSecurity(-1, { from: issuer }));
    await shouldFail.reverting(fixedPriceTender.updatePaymentPerSecurity(0, { from: issuer }));
  });

  it("should not allow a holder to opt in without checking total payment", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await securityToken.approve(fixedPriceTender.address, 50, { from : holderOne });
      
    await shouldFail.reverting(fixedPriceTender.optInToTender(50, { from: holderOne }));
  });

  it("should allow a holder to opt in after checking total payment", async () => {
    await paymentToken.approve(fixedPriceTender.address, 2000, { from : issuer });
    await fixedPriceTender.paymentTokensReady({ from: issuer });

    await securityToken.approve(fixedPriceTender.address, 50, { from : holderOne });      
    await fixedPriceTender.optInToTender(50, { from: holderOne });

    const totalTendered = await fixedPriceTender.overallTotalTendered.call();
    assert.strictEqual(parseInt(totalTendered), 50, "Total tendered does not reflect holder's tender"); 
  });

});
