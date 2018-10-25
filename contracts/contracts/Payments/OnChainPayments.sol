pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

contract OnChainPayments is Ownable {
    using ECDSA for bytes32; 
    using SafeMath for uint256;

    enum ChallengeState { NotChallenged, Challenged, Resolved }

    struct Payment {
        // Payment allocated at this time
        uint256 timestamp;
        // Value of tokens to be disbursed
        uint256 value;
        //Storing challenge state in struct for now, defaults to NoChallenge
        ChallengeState state; 
    }


    event PaymentAllocated(address _securityHolder, uint256 index, uint256 _paymentValue);
    event PaymentChallenged(address _securityHolder, uint256 _index, uint256 _suggestedValue);
    event PaymentUpdated(address _securityHolder, uint256 _index, uint256 _oldValue, uint256 _newValue);
    event PaymentResolved(address _securityHolder, uint256 _index, bool _paymentChanged);
    
    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;  
        
    //Number not available in array
    int256 public constant DOESNT_EXIST = -1;  

    //Address will be per each security token holder
    mapping(address => Payment[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;
    IERC20 public paymentToken; 

    /**
	* @dev Constructor to initialize the contract.
	* @param _securityToken Address of security token with which to apply Payment.
    * @param _paymentToken Address of stable coin with which to pay Payment. 
    * @param _issuer Address of issuer or whomever will be managing Payment. 
	*/
    constructor(IERC20 _securityToken, IERC20 _paymentToken, address _issuer) public {
        require(_securityToken != address(0) && _paymentToken != address(0), "Token addresses cannot be zero.");
        securityToken = _securityToken;
        paymentToken = _paymentToken; 
        transferOwnership(_issuer);    
    }
    
    /**
	* @dev Allows issuer to makes payments to security holders.
	* @param _securityHolders Array of addresses that are security token holders. 
    * @param _paymentPerSecurity The Payment per security owned, used to calcuate total value owed. 
    * Issuer must approver this contract to transfer their stable coin prior to this transaction.
    */
    function makePayments(address[] _securityHolders, uint256 _paymentPerSecurity) 
        public 
        onlyOwner 
    {
        require(_securityHolders.length > 0, "Empty array of addresses cannot be submitted.");
        require(_paymentPerSecurity > 0, "No value of payment per security provided.");

        for (uint256 i = 0; i < _securityHolders.length; i++){
            uint256 securitiesOwned = securityToken.balanceOf(_securityHolders[i]);
            require(securitiesOwned > 0, "Holder does not own any securities.");
            uint256 paymentOwed = securitiesOwned.mul(_paymentPerSecurity);

            payments[_securityHolders[i]].push(Payment(now, paymentOwed, ChallengeState.NoChallenge));
            paymentToken.transferFrom(issuer, _securityHolders[i], paymentOwed);

            emit PaymentAllocated(_securityHolders[i], paymentOwed);
        }
    }

    /**
	* @dev Allows the front end to calculate the index based on the offchainPayment and holder information. 
    * @param _securityHolder The address whom the payment was for
    * @param _timestamp The timestamp of when the payment occurred. 
    * @param _value The value of the payment
    * @return The index of the payment for the respective security token holder.  
    */
    function lookUpPaymentIndex(address _securityHolder, uint256 _timestamp, uint256 _value)
        public
        view
        returns(int256)
    {
        require(_timestamp != 0, "No timestamp provided.");
        require(_securityHolder != address(0), "No security holder address provided");

        Payment[] memory holderPayments = payments[_securityHolder];
        require (holderPayments.length > 0, "holder has no payment history");

        for (int256 i = holderPayments.length-1; i >= 0; i--){
            if (holderPayments[i].timestamp == _timestamp && holderPayments[i].value == _value)
            {
                return i;
            } 
        }
        return DOESNT_EXIST;
    } 

    /**
	* @dev Allows a security holder to challenge a payment they have received. 
	* @param _holder Address of holder to check Payment.  
    * @param _index Position of Payment in array of user Payments to check.
    * @param _sig Returned data from signature of hash of the (holder and index). 
    */
    function challengePayment(uint256 _timestamp, uint256 _currentValue, uint256 _suggestedValue) public {        
        int256 paymentIndex = lookUpPaymentIndex(msg.sender, _timestamp, _currentValue);
        require(paymentIndex >= 0, "Payment does not exist for provided hash");
        
        require(payments[msg.sender][paymentIndex].state == ChallengeState.NotChallenged, "Payment previously challenged.");
        require(payments[msg.sender][paymentIndex].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");
        payments[msg.sender][paymentIndex].state = ChallengeState.Challenged;

        emit PaymentChallenged(msg.sender, _timestamp, _currentValue, _suggestedValue);
    }

    /**
	* @dev Allows issuer to resolve the Payment record that has been challenged. 
	* @param _holder Address of holder to resolve Payment.  
    * @param _index Position of Payment in array of user Payment to resolve. 
    * @param _newValue New, corrected value for the Payment.
    */
    function resolveChallenge(
        address _securityHolder, 
        uint256 _timestamp,
        uint256 _currentValue,
        uint256 _newValue
    ) 
        public 
        onlyOwner 
    {    
        int256 paymentIndex = lookUpPaymentIndex(msg.sender, timestamp, _currentValue);
        require(paymentIndex >= 0, "Payment does not exist for provided hash");
        bool updated = true;
        if (_newValue == _currentValue) {
            updated = false;
        } else if (_newValue > _currentValue) {
            emit PaymentUpdated(_securityHolder, paymentIndex, _currentValue, _newValue);

            payments[_securityHolder][paymentIndex].value = _newValue;

            uint256 paymentOwed = _newValue.sub(_currentValue);
            paymentToken.transferFrom(owner, _securityHolder, paymentOwed);
        } else {
            emit PaymentUpdated(_securityHolder, paymentIndex, _currentValue, _newValue);
            payments[_securityHolder][paymentIndex].value = _newValue;
        }

        payments[_securityHolder][paymentIndex].state = ChallengeState.Resolved;
        emit PaymentResolved(_securityHolder, updated);
    }
 
}