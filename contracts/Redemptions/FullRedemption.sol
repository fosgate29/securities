pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./RedeemableToken.sol";

contract FullRedemption is Ownable {
    using SafeMath for uint256;

    IERC20 _paymentToken;
    RedeemableToken _securityToken;
    address _paymentOwner;
    uint256 _paymentPerSecurity;

    /**
	* @dev Constructor to initialize the contract.
    * @param _paymentToken The token to be used as payment.
    * @param _securityToken The security token itself.
    * @param _paymentOwner The address where the payment tokens are stored. 
    * @param _paymentPerSecurity Value to pay per security redeemed.
    */
    constructor (
        IERC20 _paymentToken,
        RedeemableToken _securityToken,
        address _paymentOwner,
        uint256 _paymentPerSecurity
    ) public {
        require(address(_paymentToken) != 0, "Payment token contract required");
        require(address(_securityToken) != 0, "Security token contract required");
        require(address(_paymentOwner) != 0, "Payment owner address required");
        require(_paymentPerSecurity > 0, "No payment amount provided");

        // Check this contract has access to enough payment tokens.
        uint256 totalPayment = securityToken.totalSupply() * _paymentPerSecurity;
        require(
            _paymentToken.allowance(paymentOwner, address(this)) >= totalPayment,
            "Redemption contract does not have access to enough tokens"
        );
        paymentToken = _paymentToken;
        securityToken = _securityToken;
        paymentOwner = _paymentOwner;
        paymentPerSecurity = _paymentPerSecurity;
    }

    /**
	* @dev Function to redeem the tokens of a group of security holders.
    * @param _holders A list of addresses of security holders.
    */
    function redeemTokens(address[] _holders) public onlyOwner {
        require(_holders.length > 0, "Empty array provided");

        // Loops through the list of holders, redeeming their tokens.
        for (uint256 i = 0; i < _holders.length; i++) {
            uint256 balance = securityToken.balanceOf(_holders[i]);
            require(balance > 0, "Holder does not own any securities.");

            // Redeem the securities and transfer the payment.
            securityToken.redeemAllTokens(_holders[i]);
            paymentToken.transferFrom(paymentOwner, _holders[i], balance*paymentPerSecurity);
        }
    }

}
