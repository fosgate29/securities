pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./Interfaces/SecurityTokenI.sol"; 

contract SecurityToken is SecurityTokenI, Ownable, ERC20Detailed, ERC20Mintable {

	/**
	* @dev Constructor to initialize the contract.
	* @param _initialSupply Total supply of tokens.
    * @param _name Is the long name by which the token contract should be known
    * @param _symbol The set of capital letters used to represent the token e.g. DTH.
    * @param _decimals The number of decimal places the tokens can be split up into. This should be between 0 and 18.
    * @param _issuer The address of issuer of the security - can mint additional security tokens and burn tokens.
	*/
    constructor(
        uint256 _initialSupply,
        string _name,
        string _symbol,
        uint8 _decimals, 
        address _issuer
    ) ERC20Detailed (_name, _symbol, _decimals) public {
        require(_initialSupply != 0, "Supply should be greater than 0.");
        mint(_issuer, _initialSupply);
        addMinter(_issuer);
        _removeMinter(msg.sender); //Remove the ability to mint/burn tokens from account deploying the security. If deploying and minting from same account would need to alter this. 
        emit Transfer(address(0), _issuer, _initialSupply);  
    }

    /* In this case, the assumption is the minter (creator of additional security tokens) would also
    have the capabilityt to burn tokens, which would be needed in the case of a security holder losing
    access to their private keys. */
    /**
	* @dev Allows same party who does the minting to burn security tokens as well.
	* @param _amount Amount of tokens to burn.
    * @param _account The address from which to burn the tokens.
	*/

    function burnSecurities(address _account, uint256 _amount) public onlyMinter {
        _burn(_account, _amount);
    }
}

/* Questions

- Do we want to set a blanket initial supply as above? 
- If we want to mint as we go, does each security have to have its own unique ID (more 721ish)?
- If it does have to have a unique identifier, these would be ERC721's.
- Minting and burning - Do we need to seperate that kind of functionality? 
- Do we need to have the ability to cap the amount that can be minted? (i.e. number of securities created)
- TBD - Use token controller for transfer restrictions
*/