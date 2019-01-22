import Promise from "bluebird";
import increaseTime, { duration } from "./helpers/increaseTime";
import latestTime from './helpers/latestTime';
import expectThrow from "./helpers/expectThrow";

web3.eth = Promise.promisifyAll(web3.eth);

const FullRedemption = artifacts.require("FullRedemption");
const RedeemableToken = artifacts.require("RedeemableToken");

contract("FullRedemption", accounts => {
  let fullRedemption;

  const issuer = accounts[0];
  const tokenOwner = accounts[1];
  const paymentOwner = accounts[2];

  let token = await RedeemableToken.new({ from: tokenOwner });

  const initialWei = 1000;
  const disbursementWei = 2000;
  const disbursementDuration = duration.weeks(5);

  beforeEach(async () => {
    vault = await Vault.new(
      wallet,
      initialWei,
      disbursementWei,
      disbursementDuration,
      { from: owner }
    );
  });

  it("should be owned by owner", async () => {
    const currentOwner = await vault.owner.call();
    assert.strictEqual(currentOwner, owner, "Contract is not owned by owner");
  });

});
