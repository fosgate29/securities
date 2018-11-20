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

    event PaymentEvent(
        address indexed _securityHolder,
        uint256 indexed _index,
        uint256 indexed _eventType,
        uint256 _value
    );
    
    // event types for the Payment event
    uint256 public constant CREATED = 1;
    uint256 public constant CHALLENGED = 2;
    uint256 public constant RESOLVED_NO_CHANGE = 3;
    uint256 public constant RESOLVED_CHANGED = 4;

    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;
    
    //Number not available in array
    int256 public constant DOESNT_EXIST = -1;   
    uint256 public constant NO_NEW_VALUE = 0x0;  

    //Address will be per each security token holder
    mapping(address => Payment[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;
    IERC20 public paymentToken; 

    modifier indexInRange(address _payee, uint256 _index) {
        require(payments[_payee].length > _index && _index >= 0, "Payment index not in range for message sender");
        _;
    }

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

            payments[_securityHolders[i]].push(Payment(now, paymentOwed, ChallengeState.NotChallenged));
            paymentToken.transferFrom(owner(), _securityHolders[i], paymentOwed);

            emit PaymentEvent(_securityHolders[i], payments[_securityHolders[i]].length-1, CREATED, paymentOwed);
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

        for (uint256 i = holderPayments.length-1; i >= 0; i--){
            if (holderPayments[i].timestamp == _timestamp && holderPayments[i].value == _value)
            {
                return int256(i);
            } 
        }
        return DOESNT_EXIST;
    } 

    /**
	* @dev Allows a security holder to challenge a payment they have received. 
    * @param _index Position of Payment in array of user Payments to check.
    * @param _suggestedValue Returned data from signature of hash of the (holder and index). 
    */
    function challengePayment(uint256 _index, uint256 _suggestedValue)
        public
        indexInRange(msg.sender, _index)
    {        
        require(payments[msg.sender][_index].state != ChallengeState.Challenged(), "Payment already being challenged.");
        require(payments[msg.sender][_index].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");
        payments[msg.sender][_index].state = ChallengeState.Challenged;

        emit PaymentEvent(msg.sender, _index, CHALLENGED, _suggestedValue);
    }

    /**
	* @dev Allows issuer to resolve the Payment record that has been challenged. 
	* @param _securityHolder Address of holder to resolve Payment.  
    * @param _index Position of Payment in array of user Payment to resolve. 
    * @param _newValue New, corrected value for the Payment.
    */
    function resolveChallenge(
        address _securityHolder, 
        uint256 _index,
        uint256 _newValue
    ) 
        public 
        onlyOwner
        indexInRange(_securityHolder, _index)
    {    
        require(payments[_securityHolder][_index].state != ChallengeState.Challenged(), "Payment is not in challenged state");
        uint256 currentValue = payments[_securityHolder][_index].value;
        if (currentValue == _newValue) {
            emit PaymentEvent(_securityHolder, _index, RESOLVED_NO_CHANGE, NO_NEW_VALUE);

        } else if (_newValue > currentValue) {
            emit PaymentEvent(_securityHolder, _index, RESOLVED_CHANGED, _newValue);

            payments[_securityHolder][_index].value = _newValue;
            uint256 paymentOwed = _newValue.sub(currentValue);
            paymentToken.transferFrom(owner(), _securityHolder, paymentOwed);

        } else {
            emit PaymentEvent(_securityHolder, _index, RESOLVED_CHANGED, _newValue);

            payments[_securityHolder][_index].value = _newValue;
        }

        payments[_securityHolder][_index].state = ChallengeState.Resolved;
    }
 
}