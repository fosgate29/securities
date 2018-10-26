pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @title Token base contract - Defines basic structure for a token
 *
 * @dev ControllableToken is a StandardToken, an OpenZeppelin ERC20 implementation library. ERC20 is also an OpenZeppelin contract.
 * More info about them is available here: https://github.com/OpenZeppelin/zeppelin-solidity/tree/master/contracts/token/ERC20
 */
contract Token is ERC20, Ownable {

    address redemption;

    modifier onlyRedemption {
        require(redemption != address(0), "No redemption contract set");
        require(msg.sender == redemption, "Only redemption contract can call this function");
        _;
    }

	/**
	* @dev Transfer is an event inherited from ERC20Basic.sol interface (OpenZeppelin).
	* @param _supply Total supply of tokens.
	*/
    constructor(uint256 _supply) public {
        require(_supply != 0, "Supply should be greater than 0.");
        totalSupply_ = _supply;
        balances[msg.sender] = _supply;
        emit Transfer(address(0), msg.sender, _supply);  //event
    }

    function setRedemption(address _redemption) external onlyOwner {
        require(_redemption != address(0), "Redemption must not have 0 address");
        redemption = _redemption;
    }

    function redeemAllTokens(address _holder) external onlyRedemption {
        uint256 balance = balances[_holder];
        require(balance > 0, "Holder has no tokens");
        emit Transfer(_holder, owner(), balance);
        balances[owner()] = balance;
        balances[_holder] = 0;
    }
}
