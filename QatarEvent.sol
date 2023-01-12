// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract DistantFinancePrediction is ReentrancyGuard, Ownable, Pausable{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    enum Choices {None, HomeWin, DrawGame, AwayWin}
    address public admin;
    uint private fees;
    uint public totalBetValuePlaced;
    struct Results {
        uint Home_score;
        uint Away_score;
    }
    struct Match {
        string HomeTeam;
        string AwayTeam;
        uint16 homeCount;
        uint16 awayCount;
        uint16 drawCount;
        uint startTime;
        uint endTime;
        uint predictionsValue;
        Results results;
        Choices gameResult;
    }
    struct User{
        Choices userPredictionChoice;
        uint winAmounts;
        uint stake;
        bool played;
    }
    mapping (uint => EnumerableSet.AddressSet) private players;
    mapping (address => mapping (uint => User)) public userPrediction;
    Match [] public allGames;
 
    constructor(){
        admin = msg.sender;
        Ownable(msg.sender);
    }
    modifier isAdmin() {
        require(_msgSender() == admin, "Caller != Protocol Admin");
        _;
    }
    
    event Pause(string reason);
    event Unpause(string reason);
    event PredictionMade(address user, Choices choice);
    event PredictionUpdate(address user, Choices choice);
    event instantiateMatchEvent(string homeTeam, string awayTeam, uint startTime);
    event updateMatchEvent(string homeTeam, string awayTeam, uint startTime);
    event closeMatchEvent(uint homeTeamScore, uint awayTeamScore);

    function fetchAllPredictionsForAnEpoch(uint epoch) external view returns (uint, uint, uint) {
        uint homeChoices = allGames[epoch].homeCount;
        uint drawChoices = allGames[epoch].drawCount;
        uint awayChoices = allGames[epoch].awayCount;
        return(homeChoices, drawChoices, awayChoices);
    }

    function fetchAddressAndPredictions(uint epoch) external view returns(address[] memory users, Choices[] memory choice) {
        uint length = players[epoch].length();
       address[] memory _users = _getPlayers(epoch);
       users = new address[](length);
       choice = new Choices[](length);
       for (uint i = 0; i < length; i++){
            users[i] = _users[i];
            choice[i] = userPrediction[_users[i]][epoch].userPredictionChoice;   
       }
       return(users, choice);
    }

    function instantiateMatch(string calldata _HomeTeam, string calldata _AwayTeam, uint _startTime) external isAdmin whenNotPaused returns (bool) { 
        uint matchEnd = _startTime + 2 hours;
        Results memory startingResults = Results(0, 0);
        allGames.push(Match(_HomeTeam, _AwayTeam, 0, 0, 0, _startTime, matchEnd, 0, startingResults, Choices.None));
        emit instantiateMatchEvent(_HomeTeam, _AwayTeam, _startTime);
        return true;
    }

    function updateInstantiatedMatch(uint epoch, string calldata _HomeTeam, string calldata _AwayTeam, uint _startTime) external isAdmin whenNotPaused returns (bool) {
        uint matchEnd = _startTime + 2 hours;
        Results memory startingResults = Results(0, 0);
        allGames[epoch] = Match(_HomeTeam, _AwayTeam, 0, 0, 0, _startTime, matchEnd, 0, startingResults, Choices.None);
        emit updateMatchEvent(_HomeTeam, _AwayTeam, _startTime);
        return true;
    }

    function closeMatch(uint epoch, uint _homeScore, uint _awayScore) external isAdmin nonReentrant { 
        uint currentTime = block.timestamp;
        require(currentTime >= allGames[epoch].endTime, "Match is still on");        
        Results memory closingResults = Results(_homeScore, _awayScore);        
        allGames[epoch].results = closingResults;        
        _checkMatchResult(epoch, _homeScore, _awayScore);        
        _calculateGameWinners(epoch, allGames[epoch].gameResult);        
        emit closeMatchEvent(_homeScore, _awayScore);
    }

    function placePrediction(uint epoch, Choices _predictionChoice) external payable nonReentrant whenNotPaused returns (bool) {
        require(msg.value == 1 ether, "userPredictionChoice Amount is not equal to 1 KCS");
        require(_predictionChoice != Choices.None, "Cannot make a null choice");        
        require(userPrediction[msg.sender][epoch].played == false, "You can only play once! Update instead");
        uint currentTime = block.timestamp;
        require(currentTime < allGames[epoch].startTime, "Game has started");
        userPrediction[msg.sender][epoch] = User(_predictionChoice, 0, 1, true);
        players[epoch].add(msg.sender);
        allGames[epoch].predictionsValue += 1 ether;
        totalBetValuePlaced += 1;
        if(_predictionChoice == Choices.HomeWin){
            allGames[epoch].homeCount += 1;
        }
        if(_predictionChoice == Choices.AwayWin){
            allGames[epoch].awayCount += 1;
        }
        if(_predictionChoice == Choices.DrawGame){
            allGames[epoch].drawCount += 1;
        }
        emit PredictionMade(msg.sender, _predictionChoice);
        return true;
    }

    function getPlayers(uint epoch) external view returns(address[] memory addresses) {
       return( _getPlayers(epoch));
    }

    function _getPlayers(uint epoch) internal view returns (address[] memory addresses) {
        uint length = players[epoch].length();
        addresses = new address[](length);
        for(uint i = 0; i < length; i++){
            addresses[i] = players[epoch].at(i);
        }
        return (addresses);
    }

    function updatePrediction(uint epoch, Choices _predictionChoice) external nonReentrant whenNotPaused returns (bool)  {
        uint currentTime = block.timestamp;
        require(currentTime < allGames[epoch].startTime, "Game has already begun"); 
        require(userPrediction[msg.sender][epoch].played == true, "You can only update once played!");
        Choices lastPrediction = userPrediction[msg.sender][epoch].userPredictionChoice;
        if(lastPrediction == Choices.HomeWin){
            allGames[epoch].homeCount -= 1;
        }
        if(lastPrediction == Choices.AwayWin){
            allGames[epoch].awayCount -= 1;
        }
        if(lastPrediction == Choices.DrawGame){
            allGames[epoch].drawCount -= 1;
        }
        if(_predictionChoice == Choices.HomeWin){
            allGames[epoch].homeCount += 1;
        }
        if(_predictionChoice == Choices.AwayWin){
            allGames[epoch].awayCount += 1;
        }
        if(_predictionChoice == Choices.DrawGame){
            allGames[epoch].drawCount += 1;
        }
        userPrediction[msg.sender][epoch].userPredictionChoice = _predictionChoice;
        emit PredictionUpdate(msg.sender, _predictionChoice);
        return true;
    }

    function _checkMatchResult(uint epoch, uint _homeScore, uint _awayScore) internal {
        if (_homeScore > _awayScore) {
        allGames[epoch].gameResult = Choices.HomeWin;           
        } else if (_homeScore < _awayScore) {
        allGames[epoch].gameResult = Choices.AwayWin;
        } else {
        allGames[epoch].gameResult = Choices.DrawGame;  
        }
    }

    function _calculateGameWinners(uint epoch, Choices _gameResult) internal {
        address[] memory _players = _getPlayers(epoch);
        if(_players.length > 0){
            uint amount = allGames[epoch].predictionsValue;
            uint fee = amount / 100 * 10;
            fees += fee;
            uint winValue = amount - fee;
            uint winnersCount = 0; 
            for (uint i = 0; i < _players.length; i++){
                if (userPrediction[_players[i]][epoch].userPredictionChoice == _gameResult) {
                    winnersCount += 1;
                }
            }
            uint individualWin = winValue / winnersCount;
            for (uint i = 0; i < _players.length; i++){
                if (userPrediction[_players[i]][epoch].userPredictionChoice == _gameResult) {
                    userPrediction[_players[i]][epoch].winAmounts = individualWin;
                }
            }
        }
    }

    function claim(uint epoch) external nonReentrant whenNotPaused returns (bool, bytes memory byteData) {
        uint amount = userPrediction[msg.sender][epoch].winAmounts;
        require(amount > 0, "No value to claim");
        userPrediction[msg.sender][epoch].winAmounts = 0;
        (bool sent, bytes memory data) = msg.sender.call{value: amount}("");
        require(sent, "error");
        return (sent, data);
    }

    function claimFees() external isAdmin whenNotPaused returns (bool, bytes memory byteData) { 
        require(fees > 0, "No fees to claim");
        uint amount = fees;
        fees = 0;
        (bool sent, bytes memory data) = admin.call{value: amount}("");
        require(sent, "error");
        return (sent, data);
    }

    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
    }

    function recoverContractBalance() external onlyOwner returns (bool, bytes memory byteData) {
        uint currentTime = block.timestamp;
        require(currentTime >= 1671926400, "Contract can only be recovered after the FIFA World Cup");
        (bool sent, bytes memory data) = admin.call{value: address(this).balance}("");
        require(sent, "error");
        return (sent, data);
    }
    
    function pauseProtocol(string calldata _reason) external whenNotPaused onlyOwner {
        _pause();
        emit Pause(_reason);
    }

    function unpauseProtocol(string calldata _reason) external whenPaused onlyOwner {
        _unpause();
        emit Unpause(_reason);
    }

}
