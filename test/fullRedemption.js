const Promise = require("bluebird");
// const latestTime = require("./helpers/latestTime");
// import increaseTime, { duration } from "./helpers/increaseTime";
// const expectThrow = require("./helpers/expectThrow");

web3.eth = Promise.promisifyAll(web3.eth);

const FullRedemption = artifacts.require("FullRedemption");
const PaymentToken = artifacts.require("PaymentTokenMock");

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
    securityToken = await RedeemableToken.new( issuer, 10000, { from: tokenOwner });
    paymentToken = await PaymentToken.new( paymentOwner, 1000000, { from: paymentOwner });

    securityToken.transfer(holderOne, 100, { from: issuer });
    securityToken.transfer(holderTwo, 200, { from: issuer });
    securityToken.transfer(holderThree, 300, { from: issuer });
    securityToken.transfer(holderFour, 400, { from: issuer });

    fullRedemption = await FullRedemption.new(
        paymentToken,
        securityToken,
        paymentOwner,
        5,
        { from: issuer }
    );
  });

  it("should be owned by the issuer", async () => {
    const currentOwner = await fullRedemption.owner.call();
    assert.strictEqual(currentOwner, issuer, "Contract is not owned by owner");
  });

});
