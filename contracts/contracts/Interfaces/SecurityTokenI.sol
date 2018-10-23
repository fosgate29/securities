pragma solidity 0.4.24; 

interface SecurityTokenI {
    function mint(address to, uint256 amount) external returns (bool);
    function burnSecurities(address _account, uint256 _amount) external;
}
