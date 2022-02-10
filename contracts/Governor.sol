// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WrappedStakedBandit} from "./tokens/WrappedStakedBandit.sol";

import {PercentageMath} from "./libraries/PercentageMath.sol";

import {IGovernor, Proposal} from "./interfaces/IGovernor.sol";

contract Governor is AccessControl, IGovernor {
    using PercentageMath for uint256;
    
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");

    WrappedStakedBandit public immutable wsBNDT;

    uint256 public proposalThreshold; // minimum number of votes needed to make a proposal
    uint256 public quorum; // minimum number of votes a proposal needs (as a % of supply in hundreds)
    uint256 public timelockDuration; // time after the vote has ended before it can be executed
    uint256 public voteDuration; // time the vote lasts for

    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => bool) public proposalExists;
    mapping(uint256 => Proposal) public proposalDetails;

    uint256[] public proposalIDs;

    constructor(
        address _wsBNDT,
        uint256 _proposalThreshold,
        uint256 _quorum,
        uint256 _timelockDuration,
        uint256 _voteDuration) {
        wsBNDT = WrappedStakedBandit(_wsBNDT);
        proposalThreshold = _proposalThreshold;
        quorum = _quorum;
        timelockDuration = _timelockDuration;
        voteDuration = _voteDuration;
        _grantRole(GOVERNOR, address(this));
    }

    modifier onlyProposer() {
        require(wsBNDT.getVotes(msg.sender) >= proposalThreshold, "Not enough votes");
        _;
    }

    /// @param delegatee address to delegate your votes to
    function delegate(address delegatee) public {
        wsBNDT.delegate(delegatee);
    }

    /// @param choice pass true to vote yes or false to vote no
    function vote(uint256 proposalIndex, bool choice) public {
        WrappedStakedBandit _wsBNDT = wsBNDT; // gas savings
        uint256[] memory _proposalIDs = proposalIDs; // gas savings
        Proposal memory readDetails = proposalDetails[proposalIDs[proposalIndex]]; // gas savings
        Proposal storage writeDetails = proposalDetails[proposalIDs[proposalIndex]]; // readability
        uint256 proposalID = _proposalIDs[proposalIndex];
        uint256 userBalance = _wsBNDT.balanceOf(msg.sender);
        uint256 snapshot = _wsBNDT.getPastVotes(
            msg.sender, readDetails.startBlockNumber);
        require(proposalIndex <= _proposalIDs.length, "Proposal does not exist");
        require(snapshot > 0 && userBalance > 0, "Zero voting power");
        require(hasVoted[proposalID][msg.sender] == false, "Already voted");
        require(block.timestamp <= readDetails.endTime, "Vote is over");
        hasVoted[proposalID][msg.sender] = true;
        if (userBalance > snapshot) {
            writeDetails.votes += snapshot;
            if (choice == true) {
                writeDetails.yesVotes += snapshot;
            } else {
                writeDetails.noVotes += snapshot;
            }
        } else {
            writeDetails.votes += userBalance;
            if (choice == true) {
                writeDetails.yesVotes += snapshot;
            } else {
                writeDetails.noVotes += snapshot;
            }
        }
    }

    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public onlyProposer returns (uint256) {
        uint256 _voteDuration = voteDuration; // gas savings
        uint256 proposalId = _hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        require(targets.length == values.length, "Invalid proposal length");
        require(targets.length == calldatas.length, "Invalid proposal length");
        require(targets.length > 0, "Empty proposal");
        require(proposalExists[proposalId] == false, "Proposal already exists");
        proposalExists[proposalId] = true;
        proposalIDs.push(proposalId);
        Proposal storage writeDetails = proposalDetails[proposalId];
        writeDetails.startBlockNumber = block.number;
        writeDetails.startTime = block.timestamp;
        writeDetails.endTime = block.timestamp + _voteDuration;
        writeDetails.executed = false;
        return proposalId;
    }

    function _hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function executeProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = _hashProposal(targets, values, calldatas, descriptionHash);
        uint256 _timelockDuration = timelockDuration; // gas savings
        Proposal memory readDetails = proposalDetails[proposalId]; // gas savings
        require(readDetails.executed == false, "Proposal already executed");
        require(block.timestamp > readDetails.endTime + _timelockDuration, "Voting + timelock hasn't ended");
        require(readDetails.votes >=
            wsBNDT.totalSupply().percentMul(quorum), "Quorum wasn't reached");
        require(readDetails.yesVotes > readDetails.noVotes, "Vote was not successful");
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        return proposalId;
    }

    function _execute(
        uint256, // proposalID
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 // descriptionHash
    ) internal {
        string memory errorMessage = "Call reverted without message";
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            Address.verifyCallResult(success, returndata, errorMessage);
        }
    }

    function changeProposalThreshold(uint256 newProposalThreshold) public onlyRole(GOVERNOR) {
        proposalThreshold = newProposalThreshold;
    }

    function changeQuorum(uint256 newQuorum) public onlyRole(GOVERNOR) {
        quorum = newQuorum;
    }

    function changeTimelockDuration(uint256 newTimelockDuration) public onlyRole(GOVERNOR) {
        timelockDuration = newTimelockDuration;
    }

    function changeVoteDuration(uint256 newVoteDuration) public onlyRole(GOVERNOR) {
        voteDuration = newVoteDuration;
    }
}