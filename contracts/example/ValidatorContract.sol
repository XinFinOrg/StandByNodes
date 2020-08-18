pragma solidity ^0.6.0;


/*

  @note - This is a dummy contract created which imitates the functions
          of the actual validator contract at 0x.....88 address 
*/

contract MasterNodeAddress {

    address[] public candidates = [0xDFf11fFf7dbe12618d77d569C863932889F514fd,0x288f4192d1c55Ec25A86b90933C6D38D8E8b99D2,0xFF720fc9e6092FDB8b319D9161Dc177a6DF98AC5];
    uint256 public minCandidateCap = 31536000000;
    
    function getCandidates() public view returns(address[] memory) {
        return candidates;
    }
            
    function getCandidateCap(address addr) public view returns(uint256) {
        if (addr==0xDFf11fFf7dbe12618d77d569C863932889F514fd) return 0;
        return minCandidateCap;
    }
        
    function test() public {
        
    }
}