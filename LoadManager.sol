// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract LoanManager {
  address public owner;
  address[] private userAddressList;
  address[] private userBorrowersList;
  address[] private userLendersList;
  uint256 public borrowersCounter;
  uint256 public lendersCounter;
  uint256 public lendAPY = 3;

  function getContractBalance() public view returns (uint256) {
    return address(this).balance;
  }

  struct borrowInfo {
    string state;
    uint256 dueDate;
    uint256 APY;
    uint256 borrowAmount;
    uint256 paybackAmount;
  }

  struct lendInfo {
    int256 lendId;
    uint256 depositTime;
    uint256 amount;
  }

  mapping(address => mapping(int256 borrowId => borrowInfo)) public Borrower;
  mapping(address => int256) public borrowCount;

  mapping(address => lendInfo[]) public Lender;
  mapping(address => uint256) public interestMatured;

  mapping(address => uint256) public netPosition;
  mapping(address => bool isActive) public isAddressActive;

  constructor() {
    owner = msg.sender;
  }

  function getUserBorrowerList() public view returns (address[] memory) {
    return userBorrowersList;
  }

  function getUserLendersList() public view returns (address[] memory) {
    return userLendersList;
  }

  //Aggiunta di un untente alla propria categoria (lender/borrower) e al counter di utenti univoci.
  function checkCategoryRegistration(address[] storage list, address[] storage list2) internal {
    bool found;
    bool found2;
    //controllo che l' utente che invoca la funzione non sia già presenta nella prima categoria
    for (uint256 i = 0; i < list.length; i++) {
      if (list[i] == msg.sender) {
        found = true;
        break;
      }
    }
    //se non è presente aggiungilo
    if (!found) {
      list.push(msg.sender);
    }
    // controllo se è presente nella seconda categoria
    for (uint256 i = 0; i < list2.length; i++) {
      if (list2[i] == msg.sender) {
        found2 = true;
        break;
      }
    }
    // se non è presente in nessuna delle due liste lo aggungo anche nella lista degli utenti complessivi
    if (found == false && found2 == false) {
      userAddressList.push(msg.sender);
    }
  }

  //controllo l' intervallo delle settimane
  modifier checkWeeksRange(uint256 _weeks) {
    require(_weeks <= 260, 'Invalid week number');
    _;
  }

  //controllo l' intervallo della somma da prednere in prestito/ritirare
  modifier checkMinimalBorrow(uint256 amount) {
    require(amount > 0.2 ether, 'Minmum borrow is 0.2 Eth');
    _;
  }

  modifier checkMinimalLend() {
    require(msg.value > 0.1 ether, 'Minmum borrow is 0.1 Eth');
    _;
  }

  modifier checkNetPosition(uint256 amount) {
    require(netPosition[msg.sender] >= amount, 'Excedeed maximum withdraw');
    _;
  }

  event lendDone(address, uint256, uint256);

  function lend() public payable checkMinimalLend {
    netPosition[msg.sender] += msg.value;
    checkCategoryRegistration(userLendersList, userBorrowersList);
    lendersCounter = userLendersList.length;
    Lender[msg.sender].push(
      lendInfo({
        lendId: int256(Lender[msg.sender].length),
        depositTime: block.timestamp,
        amount: msg.value
      })
    );
    emit lendDone(msg.sender, msg.value, block.timestamp);
  }

  function getInterestMatured() public returns (uint256) {
    interestMatured[msg.sender] = calculateInterest(msg.sender);
    return interestMatured[msg.sender];
  }

  function calculateInterest(address _address) public view returns (uint256) {
    uint256 totalInterest;

    for (uint256 i = 0; Lender[_address].length > i; i++) {
      if (Lender[_address][i].amount == 0) continue;
      totalInterest +=
        ((block.timestamp - Lender[_address][i].depositTime) *
          lendAPY *
          Lender[_address][i].amount) /
        (100 * 365 days);
    }
    return totalInterest;
  }

  function withdraw(uint256 amount) public checkNetPosition(amount) {
    netPosition[msg.sender] -= amount;
    (bool result, ) = payable(msg.sender).call{ value: amount }('');
    require(result, 'Transaction failed');
  }

  function withdrawInterest() public {
    (bool success, ) = msg.sender.call{ value: calculateInterest(msg.sender) }('');
    require(success, 'Transaction failed');
    for (uint256 i = 0; Lender[msg.sender].length > i; i++) {
      Lender[msg.sender][i].depositTime = block.timestamp;
    }
  }

  function openBorrow(
    uint256 _weeks,
    uint256 amount
  ) public payable checkWeeksRange(_weeks) checkMinimalBorrow(amount) {
    int256 counter = borrowCount[msg.sender]++;
    uint256 _dueDate = block.timestamp + (_weeks * 604800);
    uint256 APY;
    if (_weeks < 24) {
      APY = 7;
    } else if (_weeks >= 24 && _weeks < 104) {
      APY = 6;
    } else if (_weeks >= 104 && _weeks <= 260) {
      APY = 5;
    }
    uint256 _paybackAmount = amount + ((amount * APY) / 100);
    (bool success, ) = msg.sender.call{ value: amount }('');
    require(success, 'Transaction failed');
    Borrower[msg.sender][counter] = borrowInfo('active', _dueDate, APY, amount, _paybackAmount);
    checkCategoryRegistration(userBorrowersList, userLendersList);
    borrowersCounter = userBorrowersList.length;
  }
}
