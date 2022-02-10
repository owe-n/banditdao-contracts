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

    mapping(uint256 => Proposal) private proposalDetails;

    uint256[] public proposalIds;

    
    /// @dev Emitted when a proposal is created
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    /// @dev Emitted when a proposal is executed
    event ProposalExecuted(uint256 proposalId);

    /// @dev Emitted when a vote is cast
    event VoteCasted(address indexed voter, uint256 proposalId, uint256 weight, bool decision);

    constructor(
        address _wsBNDT,
        uint256 _proposalThreshold,
        uint256 _quorum,
        uint256 _timelockDuration,
        uint256 _voteDuration) {
        require(_wsBNDT != address(0), "Zero address");
        wsBNDT = WrappedStakedBandit(_wsBNDT);
        proposalThreshold = _proposalThreshold;
        quorum = _quorum;
        timelockDuration = _timelockDuration;
        require(_voteDuration > 0, "Duration must be greater than zero");
        voteDuration = _voteDuration;
        _grantRole(GOVERNOR, address(this)
    );
    }

    modifier onlyProposer() {
        require(wsBNDT.getVotes(msg.sender) >= proposalThreshold, "Not enough votes");
        _;
    }

    function getProposalDetails(uint256 proposalId) public view returns (Proposal memory) {
        require(proposalExists[proposalId], "Proposal does not exist");
        return proposalDetails[proposalId];
    }

    /// @param delegatee address to delegate your votes to
    function delegate(address delegatee) public {
        wsBNDT.delegate(delegatee);
    }

    /// @param decision pass true to vote for or false to vote against
    function vote(uint256 proposalId, bool decision) public {
        WrappedStakedBandit _wsBNDT = wsBNDT; // gas savings
        Proposal memory details = proposalDetails[proposalId]; // gas savings
        Proposal storage proposal = proposalDetails[proposalId]; // readability
        uint256 userBalance = _wsBNDT.balanceOf(msg.sender);
        uint256 snapshot = _wsBNDT.getPastVotes(
            msg.sender, details.startBlockNumber);
        uint256 weight;
        require(proposalExists[proposalId] == false, "Proposal does not exist");
        require(snapshot > 0 && userBalance > 0, "Zero voting power");
        require(hasVoted[proposalId][msg.sender] == false, "Already voted");
        require(block.timestamp <= details.endTime, "Vote is over");
        hasVoted[proposalId][msg.sender] = true;
        if (userBalance > snapshot) {
            if (decision) {
                proposal.forVotes += snapshot;
                proposal.totalVotes += snapshot;
            } else {
                proposal.totalVotes += snapshot;
            }
            weight = snapshot;
        } else {
            if (decision) {
                proposal.forVotes += userBalance;
                proposal.totalVotes += userBalance;
            } else {
                proposal.totalVotes += userBalance;
            }
            weight = userBalance;
        }
        emit VoteCasted(msg.sender, proposalId, weight, decision);
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
        proposalIds.push(proposalId);
        Proposal storage proposal = proposalDetails[proposalId];
        proposal.startBlockNumber = block.number;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + _voteDuration;
        proposal.executed = false;
        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp,
            block.timestamp + _voteDuration,
            description
        );
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
        Proposal memory details = proposalDetails[proposalId]; // gas savings
        require(details.executed == false, "Proposal already executed");
        require(block.timestamp > details.endTime + _timelockDuration, "Voting + timelock hasn't ended");
        require(details.totalVotes >= wsBNDT.getPastTotalSupply(details.startBlockNumber)
            .percentMul(quorum), "Quorum wasn't reached");
        require(details.forVotes > details.totalVotes.percentMul(5000) /* 50% */, "Vote was not successful");
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        emit ProposalExecuted(proposalId);
        return proposalId;
    }

    function _execute(
        uint256, // proposalId
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

    function changeProposalThreshold(uint256 newProposalThreshold) external onlyRole(GOVERNOR) {
        proposalThreshold = newProposalThreshold;
    }

    function changeQuorum(uint256 newQuorum) external onlyRole(GOVERNOR) {
        quorum = newQuorum;
    }

    function changeTimelockDuration(uint256 newTimelockDuration) external onlyRole(GOVERNOR) {
        timelockDuration = newTimelockDuration;
    }

    function changeVoteDuration(uint256 newVoteDuration) external onlyRole(GOVERNOR) {
        voteDuration = newVoteDuration;
    }
}