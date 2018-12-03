pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./RedeemableToken.sol";

contract PartialRedemption is Ownable {
    using SafeMath for uint256;

    uint256 paymentPerSecurity;
    IERC20 paymentToken;
    RedeemableToken securityToken;
    address paymentOwner;
    uint256 paymentPerSecurity;

    constructor (
        IERC20 _paymentToken,
        RedeemableToken _securityToken,
        address _paymentOwner,
        uint256 _paymentPerSecurit
    ) public {
        require(address(_paymentToken) != 0, "Payment token contract required");
        require(address(_securityToken) != 0, "Security token contract required");
        require(address(_paymentOwner) != 0, "Payment owner address required");
        require(_paymentPerSecurity > 0, "No payment per security provided");

        paymentToken = _paymentToken;
        securityToken = _securityToken;
        paymentOwner = _paymentOwner;
        paymentPerSecurity = _paymentPerSecurity;
    }

    function redeemTokens(address[] _holders, uint256[] _numberOfTokens) public onlyOwner {
        require(_holders.length == _numberOfTokens, "The arrays must be the same length");
        require(_holders.length > 0, "The arrays must not be empty");
        for (uint256 i = 0; i < _holders.length; i++) {
            securityToken.redeemPartialTokens(_holders[i], _numberOfTokens[i]);
            paymentToken.transferFrom(paymentOwner, _holders[i], _numberOfTokens[i]*paymentPerSecurity);
        }
    }

}
