pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./RedeemableToken.sol";

contract FixedPriceTender is Ownable {
    using SafeMath for uint256;

    IERC20 paymentToken;
    RedeemableToken securityToken;

    uint256 paymentPerSecurity; // The number of payment tokens offered per security token
    uint256 totalToRepurchase; // The maximum number of securities the issuer will repurchase
    uint256 offerEndTime;

    uint256 nextTenderToAssess;
    uint256 totalRepurchased;
    uint256 overallTotalTendered;

    struct HolderTender {
        uint256[] tenderAmounts;
        uint256 holderTotalTendered;
        uint256 nextToProcess;
    }

    mapping(address => HolderTender) tenders;
    address[] orderedHolders;

    modifier isBeforeEndTime {
        require(now < offerEndTime, "The tender offer has expired");
        _;
    }

    modifier isAfterEndTime {
        require(now >= offerEndTime, "The tender offer has not yet ended");
        _;
    }

    constructor(
        uint256 _paymentPerSecurity,
        IERC20 _paymentToken,
        RedeemableToken _securityToken,
        address _issuer,
        uint256 _totalToRepurchase,
        uint256 _offerPerSecurity,
        uint256 _offerEndTime
    ) public {
        require (
            _paymentToken.allowance(_issuer, address(this)) >= _totalToRepurchase.mul(_offerPerSecurity),
            "The contract does not have access to enough payment tokens"
        );
        require(_totalToRepurchase <= _securityToken.totalSupply(), "Total to repurchase is larger than total token supply");

        paymentPerSecurity = _paymentPerSecurity;
        paymentToken = _paymentToken;
        securityToken = _securityToken;
        issuer = _issuer;
        totalToRepurchase = _totalToRepurchase;
        offerEndTime = _offerEndTime;
    }

    function updateOfferEndTime(uint256 _newOfferEnd) external onlyOwner isBeforeEndTime {
        require(_newOfferEnd >= now, "New sale end time cannot be in the past");
        offerEndTime = _newOfferEnd;
    }

    function updatePaymentPerSecurity(uint256 _newPaymentPerSecurity) external onlyOwner isBeforeEndTime {
        require(_newPaymentPerSecurity > 0, "New payment per security cannot be 0");
        paymentPerSecurity = _newPaymentPerSecurity;
    }

    function updateTotalToRepurchase(uint256 _newTotalToRepurchase) external onlyOwner isBeforeEndTime {
        require(_newTotalToRepurchase >= 0, "New payment per security cannot be negative");
        totalToRepurchase = _newTotalToRepurchase;
    }

    function optInToTender(uint256 _numberToTender) external isBeforeEndTime {
        require(_numberToTender > 0, "Must provide a number of securities to opt in");
        // create a reference so the changes update the mapping
        HolderTender storage holderTender = tenders[msg.sender];

        // calculate new total tender from holder
        uint256 newholderTotalTendered = holderTender.holderTotalTendered + _numberToTender;

        require(securityToken.balanceOf(msg.sender) >= newholderTotalTendered, "Sender does not own enough securities");
        require(
            securityToken.allowance(msg.sender, address(this)) >= newholderTotalTendered,
            "Holder has not approved contract to control securities"
        );

        // update holder's tender to reflect this addition
        holderTender.holderTotalTendered = newholderTotalTendered;
        holderTender.tenderAmounts.push(_numberToTender);

        overallTotalTendered += _numberToTender;

        // transfer these tokens from the holder to this contract
        securityToken.transferFrom(msg.sender, address(this), _numberToTender);
    }

    function optOutOfTender(uint256 _numberToRemove) external isBeforeEndTime {
        require(_numberToRemove > 0, "Must provide a number of securities to opt out");

        // create a reference so the changes update the mapping
        HolderTender storage holderTender = tenders[msg.sender];

        require(holderTender.holderTotalTendered >= _numberToRemove, "Sender has not tendered enough securities");

        // update holder's tender to reflect this addition
        uint256 remainingToRemove = _numberToRemove;
        uint256 currentTender;
        uint256 currentIndex = holderTender.tenderAmounts.length-1;
        uint256 toRemove;

        while (remainingToRemove > 0) {
            // get amount of final array element
            currentTender = holderTender.tenderAmounts[currentIndex];

            toRemove = Math.min(currentTender, remainingToRemove);
            remainingToRemove -= toRemove;
            holderTender.tenderAmounts[currentIndex] -= toRemove;
            currentIndex -= 1;
        }

        holderTender.holderTotalTendered -= _numberToRemove;
        overallTotalTendered -= _numberToRemove;

        // transfer these tokens from the holder to this contract
        securityToken.transfer(msg.sender, _numberToRemove);
    }

    function finaliseTender(uint256 _batchSize) external isAfterEndTime {
        // These requires are kind of redundant because of the while?
        require(nextTenderToAssess < orderedHolders.length, "Finalisation is complete");
        require(_batchSize > 0, "No batch size provided");
        uint256 tendersProcessed = 0;
        while(tendersProcessed < _batchSize && nextTenderToAssess < orderedHolders.length) {
            if(totalRepurchased < totalToRepurchase) {
                repurchaseTender();
            } else {
                returnTender();
            }
            nextTenderToAssess++;
            tendersProcessed++;
        }
    }

    function repurchaseTender() internal {
        address holder = orderedHolders[nextTenderToAssess];
        HolderTender storage holderTender = tenders[msg.sender];
        uint256 nextToProcess = holderTender.nextToProcess;

        // Assert the next to process isn't beyond the end of the array
        assert(nextToProcess < holderTender.tenderAmounts.length);

        uint256 toRepurchase = Math.min(holderTender.tenderAmounts[nextToProcess], totalToRepurchase - totalRepurchased);
        securityToken.transfer(issuer, toRepurchase);
        paymentToken.transferFrom(issuer, holder, toRepurchase.mul(paymentPerSecurity));

        totalRepurchased += toRepurchase;

        // If not all of them could be repurchased, the rest must be returned
        if (toRepurchase < holderTender.tenderAmounts[nextToProcess]) {
            holderTender.tenderAmounts[nextToProcess] -= toRepurchase;
            securityToken.transfer(holder, holderTender.tenderAmounts[nextToProcess]-toRepurchase);
        }
        holderTender.nextToProcess++;
    }

    function returnTender() internal {
        address holder = orderedHolders[nextTenderToAssess];
        HolderTender storage holderTender = tenders[msg.sender];
        uint256 nextToProcess = holderTender.nextToProcess;

        // Assert the next to process isn't beyond the end of the array
        assert(nextToProcess < holderTender.tenderAmounts.length);

        // Return the tokens to the security holder
        securityToken.transfer(holder, holderTender.tenderAmounts[nextToProcess]);
        holderTender.nextToProcess++;
    }

}