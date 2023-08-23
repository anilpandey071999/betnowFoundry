// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// The MatchFactory contract allows the owner to create new Match contracts and declare results for them.
contract MatchFactory is Ownable {
    // Stores the address of each match based on its matchId.
    mapping(uint16 => address) public matchAddresses;
    // Keeps track of the total number of matches created.
    uint16 public matchCount = 0;

    event MatchCreated(uint16 matchId, address matchAddress);
    error MaxMatch();  // Error when the maximum match count is exceeded.

    // Creates a new Match contract.
    function createMatch(address _token) external onlyOwner {
        if (matchCount > 65_535) revert MaxMatch();

        Match newMatch = new Match({_owner: owner(), _token: _token, _factory: address(this) });
        matchAddresses[matchCount] = address(newMatch);
        emit MatchCreated(matchCount, address(newMatch));

        matchCount++;
    }

    // Declares the result of a specific match.
    function declareResult(uint16 matchId, uint256 winningTeam) external onlyOwner {
        Match matchInstance = Match(matchAddresses[matchId]);
        matchInstance.setResult(winningTeam);
    }

    // Allows the owner to withdraw funds from a specific match in case of emergencies.
    function emergencyWithdrawFromMatch(uint16 matchId) external onlyOwner {
        Match(matchAddresses[matchId]).emergencyWithdraw();
    }
}

// The Match contract represents a betting match where users can bet on one of two teams.
contract Match is Ownable {
    using SafeERC20 for IERC20;

    error InvalidTeam();
    error BettingClosed();
    error ResultDeclaredAlready();
    error NotFactory();
    error MatchNotDecided();
    error IncorrectTeam();

    address public factory;  // Address of the MatchFactory contract.
    IERC20 public token;     // ERC20 token used for betting.
    uint256 public treasury; // Amount of tokens reserved by the contract.

    // Structure to represent a user's bet.
    struct Bet {
        uint256 amount; // Amount bet by the user.
        uint256 team;   // Team chosen by the user: 1 or 2.
    }

    uint256 public totalBetTeamA;
    uint256 public totalBetTeamB;
    uint256 public winner; // Winner of the match: 0 (not decided), 1 (Team A), or 2 (Team B).

    // Mapping to store bets made by each user.
    mapping(address => Bet) public bets;

    event BetPlaced(address indexed user, uint256 team, uint256 amount);
    event ResultDeclared(uint256 winningTeam);
    event RewardClaimed(address indexed user, uint256 amount);

    // Constructor initializes the contract with owner, factory and token addresses.
    constructor(address _owner, address _factory, address _token) {
        transferOwnership(_owner);
        factory = _factory;
        token = IERC20(_token);
    }

    // Ensures that the calling contract is the MatchFactory.
    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    // Allows a user to bet on a team.
    function bet(uint256 team, uint256 amount) external {
        if (winner != 0) revert BettingClosed();
        if (team != 1 && team != 2) revert InvalidTeam();
        
        token.safeTransferFrom(msg.sender, address(this), amount);

        if (team == 1) {
            totalBetTeamA += amount;
        } else {
            totalBetTeamB += amount;
        }
        
        bets[msg.sender] = Bet(amount, team);
        emit BetPlaced(msg.sender, team, amount);
    }

    // Declares the winning team for the match.
    function setResult(uint256 winningTeam) external onlyFactory {
        if (winningTeam != 1 && winningTeam != 2) revert InvalidTeam();
        if (winner != 0) revert ResultDeclaredAlready();

        winner = winningTeam;

        if(winningTeam == 1) {
            treasury = (totalBetTeamB * 25) / 100;
        } else {
            treasury = (totalBetTeamA * 25) / 100;
        }

        emit ResultDeclared(winningTeam);
    }

    // Allows a user to claim their reward if they bet on the winning team.
    function claimReward() external {
        if (winner == 0) revert MatchNotDecided();
        Bet storage userBet = bets[msg.sender];
        if (userBet.team != winner) revert IncorrectTeam();

        uint256 winningPool = (winner == 1) ? totalBetTeamA : totalBetTeamB;
        uint256 loserPool = (winner == 1) ? totalBetTeamB : totalBetTeamA;

        uint256 rewardRatio = (userBet.amount * 1e18) / winningPool;
        uint256 reward = ((loserPool - treasury) * rewardRatio) / 1e18;
        uint256 totalReward = userBet.amount + reward;

        token.safeTransfer(msg.sender, totalReward);
        emit RewardClaimed(msg.sender, totalReward);
    }

    // Emergency function to transfer all tokens back to the owner.
    function emergencyWithdraw() external onlyFactory {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}
