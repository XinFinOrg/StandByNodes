pragma solidity ^0.6.0;

import "./Ownable.sol";

interface ValidatorContract {
    function getCandidates() external view returns(address[] memory);
    function candidates(uint256) external pure returns(address);
    function minCandidateCap() external pure returns(uint256);
    function getCandidateCap(address) external view returns(uint256);
}


contract StakingRewards is Ownable {
    

    uint256 public masternodeBalance;
    uint256 public annualDripMasternode;
    uint256 public annualDripStandby;
    uint256 public interestMasternode;
    uint256 public interestStandby;
    uint256 public nextInterestStandby;
    uint256 public nextInterestMasternode;
    uint256 public dripRate;
    uint256 public nextDripRate;
    address public validatorAddr;
    ValidatorContract validatorImpl;
    
    uint256 public count=0;
    uint256 public lastDripTS=block.timestamp;
    uint256 public dripStart=block.timestamp;
    
    uint256 public totalDrippedMasternode;
    uint256 public totalDrippedStandby;
    bool public paused;
    
    uint256 yearToSeconds = 31536000;
    uint256 public dripStop = dripStart+yearToSeconds;
    
    enum NodeType { Masternode, Standby, Invalid }
    
    event InsufficientBalance(uint256 timestamp, uint256 required, uint256 current);
    event TokenDrip(uint256 indexed id,uint256 timestamp, address[] masternode,uint256 masternode_amount, address[] standby, uint256 standby_amount, uint256 remaining_balance);
    event ForceStartNextCycle(uint256 timestamp, uint256 totalDrippedMasternode, uint256 totalDrippedStandby, uint256 annualDripMasternode, uint256 annualDripStandby );
    event NewCycleStarted(uint256 timestamp);
    
    constructor(uint256 _dripRate, uint256 _interestMasternode, uint256 _interestStandby, address _validatorAddr, uint256 _masternodeBalance) public payable {
        validatorAddr=_validatorAddr;
        validatorImpl = ValidatorContract(validatorAddr);
        interestMasternode=_interestMasternode;
        nextInterestMasternode=interestMasternode;
        interestStandby=_interestStandby;
        nextInterestStandby = interestStandby;
        annualDripMasternode=interestMasternode*validatorImpl.minCandidateCap()/100;
        annualDripStandby=interestStandby*validatorImpl.minCandidateCap()/100;
        masternodeBalance = _masternodeBalance;
        dripRate = _dripRate;
        nextDripRate=dripRate;
    }
    
    
    /*
    
        @dev Main function of the contract 'DRIP'. 
        Will send tokens to the concerned parties according to the current cycle's DripInterest & DripRate.
    
    */
    
    function drip() public {
        require(paused==false,"Token Drip Paused");
        uint256 currTS = block.timestamp;
        if (currTS-dripStart >= yearToSeconds ){
            // new drip cycle
            
            /*
                @dev post drip out all the pending amount & amount as per new cycle ( if any )
                
                total balance required = old-drip-total + new-drip-total
                if balance is ok then move forward & make changes
            */
            
            // uint256 secondsSinceLastDrip_old = dripStop-lastDripTS;
            uint256 dripCount_old = uint(dripStop-lastDripTS)/dripRate; // will get floor value of intervals
            uint256 masternodeDripAmount_old = calculateDripAmount(NodeType.Masternode,currTS);
            uint256 standbyDripAmount_old = calculateDripAmount(NodeType.Standby,currTS);
            
            // uint256 secondsSinceLastDrip_new = currTS-dripStop;
            uint256 dripCount_new = uint(currTS-dripStop)/nextDripRate; // will get floor value of intervals
            uint256 masternodeDripAmount_new = calculateDripAmountNext(NodeType.Masternode);
            uint256 standbyDripAmount_new = calculateDripAmountNext(NodeType.Standby);
            
            if (dripCount_old==0 && dripCount_new==0){
                return;
            }
            
            address[] memory candidates = validatorImpl.getCandidates();
            
            address[] memory standbyNodes = new address[](candidates.length);
            uint256 standbyNodeCnt=0;
            address[] memory masternodeNodes = new address[](candidates.length);
            uint256 masternodeCnt=0;
            
            
            for(uint256 i=0;i<candidates.length;i++){
                // address payable currCandidate = address(uint160(candidates[i]));
                NodeType currNodeType = getCandidateType(candidates[i]);
                if (currNodeType==NodeType.Masternode){
                    masternodeNodes[masternodeCnt] = candidates[i];
                    masternodeCnt++;
                }else if (currNodeType==NodeType.Standby){
                    standbyNodes[standbyNodeCnt] = candidates[i];
                    standbyNodeCnt++;
                }
            }
            for(uint256 i=0;i<candidates.length;i++){
                // address payable currCandidate = address(uint160(candidates[i]));
                NodeType currNodeType = getCandidateType(candidates[i]);
                if (currNodeType==NodeType.Masternode){
                    masternodeNodes[masternodeCnt] = candidates[i];
                    masternodeCnt++;
                }else if (currNodeType==NodeType.Standby){
                    standbyNodes[standbyNodeCnt] = candidates[i];
                    standbyNodeCnt++;
                }
            }
            
            uint256 totalMasternodeAmount=masternodeNodes.length*(dripCount_old*masternodeDripAmount_old+dripCount_new*masternodeDripAmount_new);
            uint256 totalStanbyNodesAmount=standbyNodes.length*(dripCount_old*standbyDripAmount_old+dripCount_new*standbyDripAmount_new);
            
            uint256 totalDripAmount = totalStanbyNodesAmount+totalMasternodeAmount;
            if (address(this).balance < totalDripAmount){
                emit InsufficientBalance(currTS,totalDripAmount,address(this).balance);
                return;
            }
            
            
            for (uint256 i=0;i<standbyNodes.length;i++){
                address payable currPayee = address(uint160(standbyNodes[i]));
                currPayee.transfer((uint(dripStop-lastDripTS)/dripRate)*standbyDripAmount_old);
                currPayee.transfer(dripCount_new*standbyDripAmount_new);
            }
            
            for (uint256 i=0;i<masternodeNodes.length;i++){
                address payable currPayee = address(uint160(masternodeNodes[i]));
                uint256 amnt_old = (uint(dripStop-lastDripTS)/dripRate)*masternodeDripAmount_old;
                uint256 amnt_new = (uint(block.timestamp-dripStop)/nextDripRate)*masternodeDripAmount_new;
                currPayee.transfer(amnt_old);
                currPayee.transfer(amnt_new);
            }
            
            count++;
            lastDripTS=currTS;
            totalDrippedMasternode=dripCount_new*masternodeDripAmount_new;
            totalDrippedStandby=dripCount_new*standbyDripAmount_new;
            dripRate=nextDripRate;
            interestStandby=nextInterestStandby;
            interestMasternode=nextInterestMasternode;
            dripStart=currTS;
            dripStop = currTS+yearToSeconds;
            annualDripMasternode=interestMasternode*validatorImpl.minCandidateCap()/100;
            annualDripStandby=interestStandby*validatorImpl.minCandidateCap()/100;
            
            emit TokenDrip(count,block.timestamp,masternodeNodes,totalMasternodeAmount,standbyNodes, totalStanbyNodesAmount,address(this).balance); 
            emit NewCycleStarted(currTS);
            
        }else{
            // drip in the existing cycle
            uint256 secondsSinceLastDrip = currTS-lastDripTS;
            uint256 dripCount = uint(secondsSinceLastDrip)/dripRate; // will get floor value of intervals
            uint256 masternodeDripAmount = calculateDripAmount(NodeType.Masternode,currTS);
            uint256 standbyDripAmount = calculateDripAmount(NodeType.Standby,currTS);
            
            if (dripCount==0) return;
            
            address[] memory candidates = validatorImpl.getCandidates();

            
            address[] memory standbyNodes = new address[](candidates.length);
            uint256 standbyNodeCnt=0;
            address[] memory masternodeNodes = new address[](candidates.length);
            uint256 masternodeCnt=0;
            
            
            for(uint256 i=0;i<candidates.length;i++){
                // address payable currCandidate = address(uint160(candidates[i]));
                NodeType currNodeType = getCandidateType(candidates[i]);
                if (currNodeType==NodeType.Masternode){
                    masternodeNodes[masternodeCnt] = candidates[i];
                    masternodeCnt++;
                }else if (currNodeType==NodeType.Standby){
                    standbyNodes[standbyNodeCnt] = candidates[i];
                    standbyNodeCnt++;
                }
            }
            
            uint256 totalMasternodeAmount=masternodeCnt*dripCount*masternodeDripAmount;
            uint256 totalStanbyNodesAmount=standbyNodeCnt*dripCount*standbyDripAmount;
            
            uint256 totalDripAmount = totalStanbyNodesAmount+totalMasternodeAmount;
            if (address(this).balance < totalDripAmount){
                emit InsufficientBalance(currTS,totalDripAmount,address(this).balance);
                return;
            }
            
            
            for (uint256 i=0;i<standbyNodeCnt;i++){
                address payable currPayee = address(uint160(standbyNodes[0]));
                currPayee.transfer(dripCount*standbyDripAmount);
            }
            
            for (uint256 i=0;i<masternodeCnt;i++){
                address payable currPayee = address(uint160(masternodeNodes[0]));
                currPayee.transfer(dripCount*masternodeDripAmount);
            }
            
            count++;
            lastDripTS=currTS;
            totalDrippedMasternode=totalDrippedMasternode+totalMasternodeAmount;
            totalDrippedStandby=totalDrippedStandby+totalStanbyNodesAmount;
            
            emit TokenDrip(count,currTS,masternodeNodes,totalMasternodeAmount,standbyNodes, totalStanbyNodesAmount,address(this).balance);
            
        }
    }
    

    
    
    function pauseDrip() public onlyOwner {
        require(paused==false, "Token Drip already paused");
        paused=true;
    }
    
    function unpauseDrip() public onlyOwner {
        require(paused==true, "Token Drip already un-paused");
        paused=false;
    }
    
    function updateMasternodeBalance(uint256 newMasternodeBalance) onlyOwner public {
        require(newMasternodeBalance>0,"Masternode balance requirement cannot be zero");
        masternodeBalance=newMasternodeBalance;
    }
    
    function getCandidates() public view  returns (address[] memory) {
        return validatorImpl.getCandidates();
    }
    
    function getDripAmount() public view returns(uint256[2] memory) {
        uint256 currTS = block.timestamp;
        return [calculateDripAmount(NodeType.Masternode,currTS),calculateDripAmount(NodeType.Standby,currTS)];
    }
    
    function getCandidateType(address candidateAddr) public view returns(NodeType) {
        uint256 candidateCap = validatorImpl.getCandidateCap(candidateAddr);
        if (candidateCap<masternodeBalance) {
            return NodeType.Standby;
        }
        return NodeType.Masternode;
    }
    
    function updateNextDripStandby(uint256 _interest) public {
        require(_interest>0,"Interest cannot be zero");
        nextInterestStandby=_interest;
    }
    
    function updateNextDripMasternode(uint256 _interest) public {
        require(_interest>0,"Interest cannot be zero");
        nextInterestMasternode=_interest;
    }
    
    function getContractBalance() public view returns(uint){
        return address(this).balance;
    }
    
    function getDripCount() public view returns(uint) {
        uint256 secondsSinceLastDrip = block.timestamp-lastDripTS;
        uint256 dripCount = uint(secondsSinceLastDrip)/dripRate; // will get floor value of intervals
        return dripCount;
    }
    
    function forceStartNextCycle() onlyOwner public {
        uint256 currTS = block.timestamp;
        emit ForceStartNextCycle(currTS,annualDripMasternode,annualDripStandby,totalDrippedMasternode,totalDrippedStandby);
        interestMasternode=nextInterestMasternode;
        interestStandby=nextInterestStandby;
        dripStart=currTS;
        dripStop=currTS+yearToSeconds;
        totalDrippedMasternode=0;
        totalDrippedStandby=0;
        annualDripMasternode=interestMasternode*validatorImpl.minCandidateCap()/100;
        annualDripStandby=interestStandby*validatorImpl.minCandidateCap()/100;
    } 
    
    // fallback() external payable {
    // }
    
    /*
    
        Internal functions starts
    
    */
    
    function calculateDripAmount(NodeType nodeType, uint256 currTS) internal view returns(uint256){
        if (nodeType==NodeType.Masternode){
            uint256 pendingAmountMasternode = annualDripMasternode - totalDrippedMasternode;
            uint256 masternodeDripAmount = uint(pendingAmountMasternode*dripRate)/(dripStop-currTS);
            return masternodeDripAmount;
        }else if (nodeType==NodeType.Standby){
            uint256 pendingAmountStandby = annualDripStandby - totalDrippedStandby;
            uint256 standbyDripAmount = uint(pendingAmountStandby*dripRate)/(dripStop-currTS);
            return standbyDripAmount;
        }else {
            return 0;
        }
    }
    
    function calculateDripAmountNext(NodeType nodeType) internal view returns(uint256){
        if (nodeType==NodeType.Masternode){
            uint256 pendingAmountMasternode = nextInterestMasternode*validatorImpl.minCandidateCap();
            uint256 masternodeDripAmount = uint(pendingAmountMasternode*nextDripRate)/(yearToSeconds);
            return masternodeDripAmount;
        }else if (nodeType==NodeType.Standby){
            uint256 pendingAmountStandby = nextInterestStandby*validatorImpl.minCandidateCap();
            uint256 standbyDripAmount = uint(pendingAmountStandby*nextDripRate)/(yearToSeconds);
            return standbyDripAmount;
        }else {
            return 0;
        }
    }
    
    /*
    
        Will reset the drip
    
    */
    
    // function _resetDrip() internal {
    //     uint256 currTS=block.timestamp;
    //     totalDrippedMasternode=0;
    //     totalDrippedStandby=0;
    //     dripStart=currTS;
    //     dripStop=currTS+yearToSeconds;
    // }
    
}