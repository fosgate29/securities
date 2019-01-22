import Promise from "bluebird";
import increaseTime, { duration } from "./helpers/increaseTime";
import latestTime from './helpers/latestTime';
import expectThrow from "./helpers/expectThrow";

web3.eth = Promise.promisifyAll(web3.eth);

const OnChainVoting = artifacts.require("OnChainVoting");
const TokenMock = artifacts.require("RedeemableTokenMock")

contract("OnChainVoting", accounts => {
  let onChainVoting;

  const issuer = accounts[0];
  const tokenOwner = accounts[1];
  const endTime = duration.weeks(5);

  let token = await TokenMock.new(issuer, 1000000, { from: issuer });

  beforeEach(async () => {
    onChainVoting = await OnChainVoting.new(token, issuer, token, {from: issuer})
  })

  it("should be owned by owner", async () => {
    const currentOwner = await onChainVoting.owner.call();
    assert.strictEqual(currentOwner, issuer, "Contract is not owned by owner");
  });

});
