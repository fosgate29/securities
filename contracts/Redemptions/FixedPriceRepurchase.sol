pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./RedeemableToken.sol";

contract FixedPriceRepurchase is Ownable {
    using SafeMath for uint256;

    IERC20 paymentToken;
    RedeemableToken securityToken;
    address paymentOwner;

    uint256 offerPerSecurity;
    uint256 totalToRepurchase;
    uint256 saleEndTime;

    struct HolderTender {
        uint256[] tenderAmounts;
        uint256 totalTendered;
    }

    mapping(address => HolderTender) tenders;
    address[] orderedHolders;

    constructor(
        uint256 _amountPerSecurity,
        IERC20 _paymentToken,
        RedeemableToken _securityToken,
        address _paymentOrigin,
        uint256 _totalNoToRepurchase,
        uint256 _offerEndTime
    ) public {
        amountPerSecurity = _amountPerSecurity;
        paymentToken = _paymentToken;
        securityToken = _securityToken;
        paymentOrigin = _paymentOrigin;
        totalNoToRepurchase = _totalNoToRepurchase;
        offerEndTime = _offerEndTime;
    }

    function updateOfferEndTime(uint256 _newOfferEnd) external onlyOwner {
        require(_newOfferEnd >= now, "New sale end time cannot be in the past");
        offerEndTime = _newOfferEnd;
    }

    function optInToTender(uint256 _numberToTender) external {
        // create a reference so the changes update the mapping
        HolderTender storage holderTender = tenders[msg.sender];

        // calculate new total tender from holder
        uint256 newTotalTendered = holderTender.totalTendered + _numberToTender;

        require(securityToken.balanceOf(msg.sender) >= newTotalTendered, "sender does not own enough securities");
        require(
            securityToken.allowance(msg.sender, address(this)) >= newTotalTendered,
            "holder has not approved contract to control securities"
        );

        // update holder's tender to reflect this addition
        holderTender.totalTendered = newTotalTendered;
        holderTender.tenderAmounts.push(_numberToTender);

        // transfer these tokens from the holder to this contract
        securityToken.transferFrom(msg.sender, address(this), _numberToTender);
    }

    function optOutOfTender(uint256 _numberToRemove) external {
        // create a reference so the changes update the mapping
        HolderTender storage holderTender = tenders[msg.sender];

        require(_numberToRemove > 0, "must provide a number of securities to opt out");
        require(holderTender.totalTendered >= _numberToRemove, "sender has not tendered enough securities");

        // update holder's tender to reflect this addition
        uint256 remainingToRemove = _numberToRemove;
        uint256 currentTender;
        uint256 currentIndex = holderTender.tenderAmounts.length-1;
        uint256 toRemove;

        while (remainingToRemove > 0) {
            // get amount of final array element
            currentTender = holderTender.tenderAmounts[currentIndex];

            toRemove = min256(currentTender, remainingToRemove);
            remainingToRemove -= toRemove;
            holderTender.tenderAmounts[currentIndex] -= toRemove;
            currentIndex -= 1;
        }

        holderTender.totalTendered -= _numberToRemove;

        // transfer these tokens from the holder to this contract
        securityToken.transfer(msg.sender, _numberToTender);
    }

    // TODO do we need to be able to specify who is entitled to a repurchase? Or if they start one are all holders entitled to one?

}