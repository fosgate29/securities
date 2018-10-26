pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/RedemptionI.sol";

contract FullRedemption is RedemptionI, Ownable {

    uint256 paymentPerSecurity;
    IERC20 paymentToken;
    IERC20 securityToken;
    address paymentOwner;

    constructor (IERC20 _paymentToken, IERC20 _securityToken, address _paymentOwner) {
        paymentToken = _paymentToken;
        securityToken = _securityToken;
        paymentOwner = _paymentOwner;
    }

    function initialiseRedemption(uint256 _paymentPerSecurity) public onlyOwner {
        paymentPerSecurity = _paymentPerSecurity;
        uint256 numberOfSecurities = _securityToken.totalSupply();
        uint256 totalPayment = numberOfSecurities * _paymentPerSecurity;
        require(
            paymentToken.allowance(paymentOwner, address(this)) >= totalPayment,
            "Redemption contract does not have access to enough tokens"
        );
    }

    function redeemTokens(address[] _holders) public onlyOwner {
        for (uint256 i = 0; i < _holders.length; i++) {
            uint256 balance = securityToken.balanceOf(_holders[i]);
            securityToken.redeemAllTokens(_holders[i]);
            paymentToken.transferFrom(paymentOwner, _holders[i], balance*paymentPerSecurity);
        }
    }

}
