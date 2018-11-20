pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./RedeemableToken.sol";

contract FixedPriceRepurchase is Ownable {
    using SafeMath for uint256;

    uint256 offerPerSecurity;
    IERC20 paymentToken;
    RedeemableToken securityToken;
    address paymentOwner;

    uint256 totalToRepurchase;
    uint256 numberRepurchased;
    uint256 saleEndTime;

    constructor(
        uint256 _offerPerSecurity,
        IERC20 _paymentToken,
        RedeemableToken _securityToken,
        address _paymentOwner,
        uint256 _totalToRepurchase,
        uint256 _saleEndTime
    ) public {
        offerPerSecurity = _offerPerSecurity;
        paymentToken = _paymentToken;
        securityToken = _securityToken;
        paymentOwner = _paymentOwner;
        totalToRepurchase = _totalToRepurchase;
        saleEndTime = _saleEndTime;
    }

    function updateSaleEndTime(uint256 _newSaleEnd) external onlyOwner {
        require(_newSaleEnd >= now, "New sale end time cannot be in the past");
        saleEndTime = _newSaleEnd;
    }

    function confirmRepurchase(uint256 _numberOfSecurities) external {
        require(securityToken.balanceOf(msg.sender) >= _numberOfSecurities, "sender does not own enough securities");
        require(numberRepurchased < totalToRepurchase);

        uint256 paymentOwed = _numberOfSecurities * offerPerSecurity;
        paymentToken.transferFrom(paymentOwner, msg.sender, paymentOwed);
        securityToken.redeemPartialTokens(msg.sender, _numberOfSecurities);
    }

    // TODO do we need to be able to specify who is entitled to a repurchase? Or if they start one are all holders entitled to one?

}