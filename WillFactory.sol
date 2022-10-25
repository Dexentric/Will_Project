//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "./Will.sol";

/**
 * @dev Factory of will contracts each one will have his balance and properties.
 * Only one will may be created through this contract
 */
contract WillFactory {
    mapping(address => address) public willOwners; //Owner address to contract address
    event WillCreated(address _newWIll);

    function createWillContract(address payable _lawyer, uint256 _lockTime)
        external
    {
        /// @dev if you don't have a will the address should be 0x00
        require(
            willOwners[msg.sender] == address(0),
            "You already have a will contract"
        );
        //@dev the will must be locked for at least 1 day i.e 365 days
        require(_lockTime != 0, "The minimum time is 1 day");
        require(_lockTime < 366 days, "The maximun time is 365 days");
        ///@dev creates a will with a lawyer and specified lock time
        Will will = new Will(payable(msg.sender), _lawyer, _lockTime);
        /// @dev the contract address of the will is the value of the owner of it (the lawyer) which is the key in the mapping
        willOwners[msg.sender] = address(will);
        ///@dev show that a will has been created.
        emit WillCreated(willOwners[msg.sender]);
    }
        ///@dev to check if a will has been deployed by a lawyer. 
        /// It returns the will contract address when the lawyer address is passed in
    function checkWills(address _address) external view returns (address) {
        require(
            willOwners[_address] != address(0),
            "You do not have a deployed Will"
        );
        return (willOwners[_address]);
    }
}