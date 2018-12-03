pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./RedeemableToken.sol";

contract FullRedemption is Ownable {
    using SafeMath for uint256;

    uint256 paymentPerSecurity;
    IERC20 paymentToken;
    RedeemableToken securityToken;
    address paymentOwner;

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

    function redeemTokens(address[] _holders) public onlyOwner {
        require(_holders.length > 0, "Empty array provided");
        for (uint256 i = 0; i < _holders.length; i++) {
            uint256 balance = securityToken.balanceOf(_holders[i]);
            securityToken.redeemAllTokens(_holders[i]);
            paymentToken.transferFrom(paymentOwner, _holders[i], balance*paymentPerSecurity);
        }
    }

}
